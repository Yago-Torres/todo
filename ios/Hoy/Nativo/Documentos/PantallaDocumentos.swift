import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Documentos en nativo (lo de static/documentos.html): la lista por tipo, lo que caduca pronto, verlos con QuickLook,
/// guardar uno nuevo desde Archivos, el escáner o la cámara, y cambiar o borrar. Los ficheros se guardan en la base
/// local del iPhone (ver DatosDocumentos.swift) y se abren sin red; los privados piden Face ID si el bloqueo está activo.
struct PantallaDocumentos: View {
    @State private var datos = DatosDocumentos.shared
    @State private var categoria: String?
    @State private var busca = ""
    @State private var vista: URL?
    @State private var abriendo: String?
    @State private var editando: DocumentoTom?
    @State private var borrador: BorradorDocumento?
    @State private var capturado: BorradorDocumento?
    @State private var eligiendoArchivo = false
    @State private var escaneando = false
    @State private var fotografiando = false

    var body: some View {
        VStack(spacing: Tema.Espacio.m) {
            cabecera
            CampoBusqueda(texto: $busca, pista: "Buscar documentos")
                .padding(.horizontal, Tema.Espacio.l)
            SelectorPildoras(opciones: opcionesCategoria, seleccion: $categoria)
            lista
        }
        .padding(.top, Tema.Espacio.s)
        .tostada(datos.aviso) { datos.quitaAviso() }
        .task { await datos.carga() }
        .environment(\.locale, FechasES.locale)
        .quickLookPreview($vista)
        .onChange(of: vista) { _, nueva in
            if nueva == nil { DatosDocumentos.limpiaTemporales() }
        }
        .fileImporter(isPresented: $eligiendoArchivo, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { r in
            recibeArchivo(r)
        }
        .fullScreenCover(isPresented: $escaneando) {
            EscanerDocumentos(alTerminar: { pdf in
                recibe(BorradorDocumento(datos: pdf, nombre: "Escaneo \(FechasES.texto(Date(), "d MMM")).pdf", tipo: "application/pdf"))
            }, alFallar: { datos.avisa($0, error: true) }, cierra: { escaneando = false })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $fotografiando) {
            CamaraFoto(alTerminar: { jpeg in
                recibe(BorradorDocumento(datos: jpeg, nombre: "Foto \(FechasES.texto(Date(), "d MMM")).jpg", tipo: "image/jpeg"))
            }, cierra: { fotografiando = false })
            .ignoresSafeArea()
        }
        .sheet(item: $borrador) { b in
            HojaDocumento(modo: .nuevo(b), categorias: datos.categorias) { ficha in
                await datos.sube(b, ficha: ficha)
            }
        }
        .sheet(item: $editando) { d in
            HojaDocumento(modo: .cambiar(d), categorias: datos.categorias,
                          alGuardar: { ficha in await datos.edita(d, ficha: ficha) },
                          alBorrar: { await datos.borra(d) })
        }
    }

    // MARK: cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(datos.docs.count == 1 ? "1 documento" : "\(datos.docs.count) documentos")
                        .estiloEtiqueta().foregroundStyle(Tema.suave)
                        .contentTransition(.numericText())
                    Text("Documentos").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                Menu {
                    if EscanerDocumentos.disponible {
                        Button { escaneando = true } label: { Label("Escanear un documento", systemImage: "doc.viewfinder") }
                    }
                    if CamaraFoto.disponible {
                        Button { fotografiando = true } label: { Label("Hacer una foto", systemImage: "camera") }
                    }
                    Button { eligiendoArchivo = true } label: { Label("Elegir de Archivos", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.acentoTexto)
                        .frame(width: 40, height: 40)
                        .background(Tema.acento, in: Circle())
                }
                .accessibilityLabel("Guardar un documento")
            }
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            }
            Label("Se guardan solo en este iPhone, con el bloqueo del móvil, para verlos sin red.", systemImage: "lock.fill")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
        }
        .padding(.horizontal, Tema.Espacio.l)
    }

    private var opcionesCategoria: [(valor: String?, titulo: String)] {
        var o: [(valor: String?, titulo: String)] = [(valor: nil, titulo: "Todos")]
        for c in datos.categorias {
            let n = datos.todos.filter { $0.cat == c.id }.count
            if n > 0 { o.append((valor: c.id, titulo: "\(c.nombre) · \(n)")) }
        }
        return o
    }

    // MARK: lista

    private struct Seccion: Identifiable {
        let id: String
        let titulo: String
        let docs: [DocumentoTom]
        var alerta = false
    }

    private var secciones: [Seccion] {
        var out: [Seccion] = []
        if categoria == nil && busca.isEmpty && !datos.pronto.isEmpty {
            out.append(Seccion(id: "pronto", titulo: "Caducan pronto", docs: datos.pronto, alerta: true))
        }
        let visibles = datos.filtrados(categoria: categoria, buscando: busca)
        for c in datos.categorias {
            let l = visibles.filter { $0.cat == c.id }.sorted { $0.n.localizedCompare($1.n) == .orderedAscending }
            if !l.isEmpty { out.append(Seccion(id: c.id, titulo: c.nombre, docs: l)) }
        }
        return out
    }

    private var lista: some View {
        List {
            ForEach(secciones) { s in
                Section {
                    ForEach(s.docs) { d in fila(d, enPronto: s.id == "pronto") }
                } header: {
                    Text("\(s.titulo) · \(s.docs.count)")
                        .estiloEtiqueta().foregroundStyle(s.alerta ? Tema.aviso : Tema.suave)
                }
            }
            if secciones.isEmpty == false {
                Section {} footer: {
                    Text("\(datos.enLocal.count) de \(datos.docs.count) disponibles sin red.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(Tema.Espacio.m)
        .contentMargins(.bottom, 110, for: .scrollContent)   // el hueco de la barra
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await datos.recarga() }
        .overlay { vacio }
    }

    @ViewBuilder private var vacio: some View {
        if secciones.isEmpty && !datos.cargando {
            VStack(spacing: Tema.Espacio.s) {
                Image(systemName: busca.isEmpty ? "doc.text" : "magnifyingglass")
                    .font(.system(size: 34)).foregroundStyle(Tema.tenue)
                Text(busca.isEmpty
                     ? (datos.error ?? "Aún no hay nada. Empieza por el DNI, el pasaporte y los seguros.")
                     : "Nada con «\(busca)»")
                    .font(Tema.fuente(.texto)).foregroundStyle(datos.error != nil && busca.isEmpty ? Tema.peligro : Tema.suave)
                    .multilineTextAlignment(.center)
            }
            .padding(Tema.Espacio.xl)
            .allowsHitTesting(false)
        }
    }

    private func fila(_ d: DocumentoTom, enPronto: Bool) -> some View {
        FilaDocumento(documento: d, nombreTipo: datos.nombre(d.cat), enLocal: datos.enLocal.contains(d.id),
                      cargando: abriendo == d.id)
            .contentShape(Rectangle())
            .onTapGesture { abre(d) }
            .listRowBackground(Tema.carta)
            .listRowSeparatorTint(Tema.linea)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { Task { await datos.borra(d) } } label: { Label("Borrar", systemImage: "trash") }
                Button { editando = d } label: { Label("Cambiar", systemImage: "pencil") }
                    .tint(Tema.aviso)
            }
            .contextMenu {
                Button { abre(d) } label: { Label("Ver", systemImage: "eye") }
                Button { editando = d } label: { Label("Cambiar datos", systemImage: "pencil") }
                Button(role: .destructive) { Task { await datos.borra(d) } } label: { Label("Borrar", systemImage: "trash") }
            }
    }

    // MARK: acciones

    private func abre(_ d: DocumentoTom) {
        guard abriendo == nil else { return }
        Haptica.shared.toca(.marcar)
        Task {
            abriendo = d.id
            defer { abriendo = nil }
            guard await PuertaPrivada.abre(d) else { return }
            do {
                vista = try await datos.ficheroParaVer(d)
            } catch let e as APIError where e.sinRed {
                datos.avisa("Sin conexión, y este documento aún no está guardado en el iPhone. Ábrelo una vez con conexión.", error: true)
            } catch {
                datos.avisa("No he podido abrirlo: \(error.localizedDescription)", error: true)
            }
        }
    }

    private func recibeArchivo(_ r: Result<[URL], Error>) {
        switch r {
        case .failure(let e):
            datos.avisa("No he podido leer el archivo: \(e.localizedDescription)", error: true)
        case .success(let urls):
            guard let url = urls.first else { return }
            let acceso = url.startAccessingSecurityScopedResource()
            defer { if acceso { url.stopAccessingSecurityScopedResource() } }
            do {
                let bytes = try Data(contentsOf: url)
                let tipo = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                recibe(BorradorDocumento(datos: bytes, nombre: url.lastPathComponent, tipo: tipo))
            } catch {
                datos.avisa("No he podido leer el archivo: \(error.localizedDescription)", error: true)
            }
        }
    }

    /// Lo escaneado o elegido pasa a la hoja de datos cuando el selector ya se ha ido (dos presentaciones a la vez se pierden).
    private func recibe(_ b: BorradorDocumento) {
        capturado = b
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let c = capturado {
                borrador = c
                capturado = nil
            }
        }
    }
}

private struct FilaDocumento: View {
    let documento: DocumentoTom
    let nombreTipo: String
    let enLocal: Bool
    let cargando: Bool

    private var icono: String {
        switch documento.cat {
        case "identidad": return "person.text.rectangle"
        case "coche": return "car"
        case "casa": return "house"
        case "trabajo": return "briefcase"
        case "estudios": return "graduationcap"
        case "salud": return "cross.case"
        case "seguros": return "shield"
        case "garantias": return "checkmark.seal"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: Tema.Espacio.m) {
            Image(systemName: documento.provisional ? "clock" : icono)
                .font(.system(size: 17))
                .foregroundStyle(Tema.acento)
                .frame(width: 38, height: 38)
                .background(Tema.acentoSuave, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(documento.n).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(2)
                subtitulo
            }
            Spacer(minLength: Tema.Espacio.s)
            if cargando {
                ProgressView().tint(Tema.suave)
            } else if enLocal {
                Image(systemName: "iphone")
                    .font(.system(size: 13)).foregroundStyle(Tema.tenue)
                    .accessibilityLabel("Disponible sin red")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var subtitulo: some View {
        if documento.provisional {
            Text("Se subirá al volver la conexión").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
        } else {
            let v = Vigencia(documento)
            let resto = [documento.titular, documento.notas].filter { !$0.isEmpty }.joined(separator: " · ")
            if v != nil || !resto.isEmpty {
                HStack(spacing: 6) {
                    if let v {
                        Text(v.texto).foregroundStyle(v.color).fontWeight(v.nivel == .normal ? .regular : .medium)
                    }
                    if v != nil && !resto.isEmpty { Text("·").foregroundStyle(Tema.tenue) }
                    if !resto.isEmpty { Text(resto).foregroundStyle(Tema.suave).lineLimit(1) }
                }
                .font(Tema.fuente(.pequeno))
            }
        }
    }
}
