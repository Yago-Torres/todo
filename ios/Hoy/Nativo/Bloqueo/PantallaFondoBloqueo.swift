import SwiftUI
import UIKit
import PhotosUI
import WidgetKit

/// La fila que lleva a la pantalla de bloqueo. Va en SeccionAjustesTom: sale en Configurar y en Ajustes.
struct SeccionFondoBloqueo: View {
    var body: some View {
        Section {
            NavigationLink {
                PantallaFondoBloqueo()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pantalla de bloqueo")
                        Text("Tu foto con lo que toca según la hora")
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                } icon: {
                    Image(systemName: "lock.iphone").foregroundStyle(Tema.acento)
                }
            }
        } header: {
            Text("Pantalla de bloqueo")
        }
        .listRowBackground(Tema.carta)
    }
}

/// Personalizar el fondo de bloqueo: foto y encuadre, capa, qué sale en cada momento y sus horas, con la vista previa
/// en vivo a tamaño de pantalla, y los pasos para que Atajos lo ponga solo.
struct PantallaFondoBloqueo: View {
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.openURL) private var abrirURL

    @State private var ajustes = AjustesFondo.lee()
    @State private var momento: MomentoFondo = .manana
    @State private var verHora = true
    @State private var hoy: Hoy? = Almacen.leeHoy()
    @State private var inst: InstantaneaFondo? = InstantaneaFondo.lee()

    // la foto de la vista previa
    @State private var elegida: PhotosPickerItem?
    @State private var versionFoto = 0
    @State private var fuente: CGImage?
    @State private var fuenteDe: String?
    @State private var preparada: FotoPreparada?
    @State private var cargandoFoto = false
    @State private var fallo: String?
    @State private var inicioGesto: AjusteFoto?

    // probar
    @State private var generando = false
    @State private var prueba: ImagenPrueba?
    @State private var falloPrueba: String?

    private var lienzo: CGSize { PantallaFondo.puntos }
    private var claveFoto: String { FotosFondo.clave(ajustes, momento) }
    private var hayFoto: Bool { FotosFondo.existe(claveFoto) }
    private var claveProceso: String {
        "\(claveFoto)·\(versionFoto)·\(ajusteActual.desenfoque)·\(ajustes.estilo != .sombra)"
    }

    private var ajusteActual: AjusteFoto { ajustes.fotos[claveFoto] ?? AjusteFoto() }

    private var ajusteFoto: Binding<AjusteFoto> {
        Binding(get: { ajustes.fotos[claveFoto] ?? AjusteFoto() },
                set: { ajustes.fotos[claveFoto] = $0 })
    }

    var body: some View {
        Form {
            Group {
                seccionVistaPrevia
                seccionFoto
                seccionCapa
                seccionElementos
                seccionHoras
                seccionAtajos
                seccionProbar
            }
            .listRowBackground(Tema.carta)
        }
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .navigationTitle("Pantalla de bloqueo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await traeDatos() }
        .task(id: claveProceso) { preparaPrevia() }
        .task(id: ajustes) {
            // se guarda al parar de tocar (y el widget «Tom según la hora» se rehace con las horas nuevas)
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            ajustes.guarda()
            WidgetCenter.shared.reloadTimelines(ofKind: DatosFondo.tipoWidget)
        }
        .onChange(of: elegida) { _, item in
            guard let item else { return }
            Task { await usa(item) }
        }
        .sheet(item: $prueba) { p in HojaPrueba(prueba: p) }
    }

    // MARK: vista previa

    private var contenido: ContenidoMomento {
        ContenidoMomento.construye(ajustes, hoy: hoy, inst: inst, ahora: Date(), momento: momento)
    }

    private var seccionVistaPrevia: some View {
        Section {
            Picker("Momento", selection: $momento.animation(sinMovimiento ? nil : Tema.Muelle.toque)) {
                ForEach(MomentoFondo.allCases) { m in
                    Text(m.nombre).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            vistaPrevia
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: Tema.Espacio.s, leading: 0, bottom: Tema.Espacio.s, trailing: 0))

            Toggle("Ver la hora del bloqueo encima", isOn: $verHora)
        } footer: {
            Text(hayFoto ? "Arrastra la vista previa para mover la foto y pellízcala para acercarla. Las rayas marcan la zona que queda libre de la hora, los widgets y los botones."
                         : "Elige una foto abajo. Las rayas marcan la zona que queda libre de la hora, los widgets y los botones.")
        }
    }

    private var vistaPrevia: some View {
        let alto: CGFloat = 470
        let k = alto / max(1, lienzo.height)
        return TimelineView(.everyMinute) { reloj in
            LienzoFondo(lienzo: lienzo, foto: preparada, ajusteFoto: ajusteActual, ajustes: ajustes, contenido: contenido,
                        estilo: EstiloFondo.de(ajustes), horaSimulada: verHora ? reloj.date : nil)
                .environment(\.locale, Locale(identifier: "es_ES"))
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: lienzo.width * k, height: alto, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 55 * k, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 55 * k, style: .continuous)
                    .strokeBorder(Tema.linea, lineWidth: 1))
        }
        .overlay { if cargandoFoto { ProgressView().controlSize(.large) } }
        .contentShape(Rectangle())
        .gesture(gestoEncuadre(k), including: hayFoto ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa del fondo de \(momento.nombre.lowercased())")
        .accessibilityValue(resumenAccesible)
        .accessibilityHint(hayFoto ? "Arrastra para mover la foto y pellizca para acercarla." : "")
    }

    private var resumenAccesible: String {
        let c = contenido
        var partes = [c.titulo]
        if !c.faltan.isEmpty { partes.append("faltan \(c.faltan.count) hábitos") }
        if let e = c.entrenoPendiente.first { partes.append("entreno \(e.nombre)") }
        return partes.joined(separator: ", ")
    }

    private func gestoEncuadre(_ k: CGFloat) -> some Gesture {
        let arrastre = DragGesture(minimumDistance: 2)
            .onChanged { v in
                let base = inicioGesto ?? ajusteActual
                if inicioGesto == nil { inicioGesto = base }
                var a = ajusteActual
                a.x = base.x + Double(v.translation.width / (lienzo.width * k))
                a.y = base.y + Double(v.translation.height / (lienzo.height * k))
                ajusteFoto.wrappedValue = limita(a)
            }
            .onEnded { _ in inicioGesto = nil }
        let pellizco = MagnifyGesture()
            .onChanged { v in
                let base = inicioGesto ?? ajusteActual
                if inicioGesto == nil { inicioGesto = base }
                var a = ajusteActual
                a.zoom = base.zoom * Double(v.magnification)
                ajusteFoto.wrappedValue = limita(a)
            }
            .onEnded { _ in inicioGesto = nil }
        return SimultaneousGesture(arrastre, pellizco)
    }

    private func limita(_ a: AjusteFoto) -> AjusteFoto {
        guard let f = preparada?.tamano else { return a }
        return Encuadre.limita(a, f, lienzo)
    }

    /// La foto del momento a tamaño de vista previa, y sus desenfoques (rápidos: la copia es pequeña).
    private func preparaPrevia() {
        let clave = claveFoto
        guard FotosFondo.existe(clave) else {
            fuente = nil
            fuenteDe = nil
            preparada = nil
            return
        }
        let id = "\(clave)·\(versionFoto)"
        if fuenteDe != id || fuente == nil {
            fuente = FotosFondo.carga(clave, maxPx: 1400)
            fuenteDe = id
        }
        guard let fuente else { preparada = nil; return }
        preparada = ProcesaFoto.prepara(fuente, ajuste: ajusteActual, lienzo: lienzo, cristal: ajustes.estilo != .sombra)
    }

    private func traeDatos() async {
        if let r = DatosFondo.refresca() { inst = r }
        if Almacen.claves != nil, let nuevo = try? await API.hoy() { hoy = nuevo }
    }

    // MARK: foto

    private var seccionFoto: some View {
        Section {
            Toggle("La misma foto para todos los momentos", isOn: $ajustes.mismaFoto)
            PhotosPicker(selection: $elegida, matching: .images) {
                Label(hayFoto && (ajustes.mismaFoto || FotosFondo.existe(momento.rawValue)) ? "Cambiar la foto" : "Elegir una foto",
                      systemImage: "photo.on.rectangle")
            }
            if hayFoto {
                deslizador("Zoom", valor: ajusteFoto.zoom, rango: 1...4, texto: String(format: "%.1f×", ajusteActual.zoom))
                deslizador("Oscurecer", valor: ajusteFoto.oscurecer, rango: 0...0.85,
                           texto: "\(Int((ajusteActual.oscurecer * 100).rounded())) %")
                deslizador("Desenfocar", valor: ajusteFoto.desenfoque, rango: 0...1,
                           texto: "\(Int((ajusteActual.desenfoque * 100).rounded())) %")
                Button("Centrar la foto", systemImage: "arrow.down.right.and.arrow.up.left") {
                    Haptica.shared.toca(.marcar)
                    var a = ajusteActual
                    a.zoom = 1; a.x = 0; a.y = 0
                    ajusteFoto.wrappedValue = a
                }
                Button("Quitar la foto", systemImage: "trash", role: .destructive) {
                    FotosFondo.borra(claveFoto)
                    ajustes.fotos[claveFoto] = nil
                    versionFoto += 1
                }
            }
            if let fallo {
                Text(fallo).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        } header: {
            Text(ajustes.mismaFoto ? "Foto" : "Foto de \(momento.nombre.lowercased())")
        } footer: {
            Text(ajustes.mismaFoto
                 ? "Sin foto, sale un degradado con los colores del tema."
                 : "Cada momento puede tener su foto; el que no tenga usa la común (la de «La misma foto»).")
        }
    }

    private func deslizador(_ titulo: String, valor: Binding<Double>, rango: ClosedRange<Double>, texto: String) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack {
                Text(titulo)
                Spacer()
                Text(texto).monospacedDigit().foregroundStyle(Tema.suave).contentTransition(.numericText())
            }
            Slider(value: valor, in: rango)
                .accessibilityLabel(titulo)
                .accessibilityValue(texto)
        }
    }

    private func usa(_ item: PhotosPickerItem) async {
        cargandoFoto = true
        fallo = nil
        defer {
            cargandoFoto = false
            elegida = nil
        }
        do {
            guard let datos = try await item.loadTransferable(type: Data.self) else {
                throw ErrorFondo(mensaje: "No he podido abrir esa foto. Si está en iCloud, espera a que se descargue y vuelve a elegirla.")
            }
            let clave = ajustes.claveFoto(momento)
            try FotosFondo.guarda(datos, clave: clave)
            var a = ajustes.fotos[clave] ?? AjusteFoto()
            a.zoom = 1; a.x = 0; a.y = 0
            ajustes.fotos[clave] = a
            versionFoto += 1
            Haptica.shared.toca(.marcar)
        } catch {
            fallo = error.localizedDescription
            Haptica.shared.toca(.error)
        }
    }

    // MARK: capa

    private var seccionCapa: some View {
        Section {
            Picker("Estilo", selection: $ajustes.estilo) {
                ForEach(EstiloCapa.allCases) { Text($0.nombre).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Posición", selection: $ajustes.posicion) {
                ForEach(PosicionCapa.allCases) { Text($0.nombre).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Dejar sitio a los widgets del bloqueo", isOn: $ajustes.huecoWidgets)
            deslizador("Tamaño", valor: $ajustes.tamano, rango: 0.8...1.4,
                       texto: "\(Int((ajustes.tamano * 100).rounded())) %")
            Picker("Letra", selection: $ajustes.letra) {
                Text("La del tema").tag("tema")
                ForEach(Aspecto.shared.catalogo?.fuentes ?? []) { f in
                    Text(f.nombre).tag(f.id)
                }
            }
            Picker("Colores", selection: $ajustes.colores) {
                ForEach(ColoresCapa.allCases) { Text($0.nombre).tag($0) }
            }
            if ajustes.colores == .propios {
                ColorPicker("Texto", selection: color(\.textoPropio), supportsOpacity: false)
                ColorPicker("Acento", selection: color(\.acentoPropio), supportsOpacity: false)
            }
        } header: {
            Text("La capa")
        } footer: {
            Text("Cristal: una tarjeta translúcida. Texto: solo letras con sombra. Banda: una franja de lado a lado.")
        }
    }

    private func color(_ campo: WritableKeyPath<AjustesFondo, String>) -> Binding<Color> {
        Binding(get: { Color(hex: ajustes[keyPath: campo]) },
                set: { ajustes[keyPath: campo] = Self.hex($0) })
    }

    private static func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func n(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", n(r), n(g), n(b))
    }

    // MARK: elementos

    private var seccionElementos: some View {
        Section {
            ForEach(MomentoFondo.allCases) { m in
                NavigationLink {
                    EditorElementos(momento: m, ajustes: $ajustes)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(m.nombre, systemImage: m.simbolo)
                        Text(ajustes.elementos(m).filter(\.visible).map(\.elemento.nombre).joined(separator: ", "))
                            .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).lineLimit(2)
                    }
                }
            }
        } header: {
            Text("Qué sale en cada momento")
        } footer: {
            Text("Lo que no tenga nada que decir (sin tareas con hora, sin entreno…) no ocupa sitio.")
        }
    }

    // MARK: horas

    private var seccionHoras: some View {
        Section {
            DatePicker("Me despierto", selection: hora(\.despertar), displayedComponents: .hourAndMinute)
            DatePicker("Empieza la noche", selection: hora(\.noche), displayedComponents: .hourAndMinute)
            Toggle("Entreno a hora fija", isOn: $ajustes.horaFija)
            if ajustes.horaFija {
                DatePicker("Lunes a jueves", selection: hora(\.horaLaborable), displayedComponents: .hourAndMinute)
                DatePicker("Viernes", selection: hora(\.horaViernes), displayedComponents: .hourAndMinute)
                DatePicker("Fin de semana", selection: hora(\.horaFinde), displayedComponents: .hourAndMinute)
                Stepper("Empieza \(ajustes.antes) min antes", value: $ajustes.antes, in: 0...180, step: 15)
                Stepper("Dura hasta \(ContenidoMomento.horas(ajustes.duracion)) después",
                        value: $ajustes.duracion, in: 15...240, step: 15)
            } else {
                DatePicker("Desde", selection: hora(\.franjaInicio), displayedComponents: .hourAndMinute)
                DatePicker("Hasta", selection: hora(\.franjaFin), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Horas de cada momento")
        } footer: {
            Text("Mañana: desde que te despiertas. Entreno: solo si hoy falta alguno por hacer. Noche: hasta que te vas a dormir. Fuera del entreno vuelve lo del día.")
        }
    }

    private func hora(_ campo: WritableKeyPath<AjustesFondo, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(ajustes[keyPath: campo]) * 60)
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            ajustes[keyPath: campo] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    // MARK: instalar con Atajos

    private var automatizaciones: [(hora: String, dias: String, que: String)] {
        let a = ajustes
        var lista: [(Int, String, String)] = [(a.despertar, "Todos los días", "Mañana")]
        if a.horaFija {
            // las mismas horas se juntan en una automatización
            var grupos: [(inicio: Int, fin: Int, dias: [String])] = []
            for (h, dias) in [(a.horaLaborable, "lunes a jueves"), (a.horaViernes, "viernes"), (a.horaFinde, "sábado y domingo")] {
                if let i = grupos.firstIndex(where: { $0.inicio == h - a.antes }) {
                    grupos[i].dias.append(dias)
                } else {
                    grupos.append((h - a.antes, h + a.duracion, [dias]))
                }
            }
            for g in grupos {
                let dias = g.dias.count == 3 ? "Todos los días" : g.dias.joined(separator: ", ").capitalizedPrimera
                lista.append((g.inicio, dias, "Entreno"))
                lista.append((g.fin, dias, "Vuelve lo del día"))
            }
        } else {
            lista.append((a.franjaInicio, "Todos los días", "Entreno"))
            lista.append((a.franjaFin, "Todos los días", "Vuelve lo del día"))
        }
        lista.append((a.noche, "Todos los días", "Noche"))
        return lista.sorted { $0.0 < $1.0 }.map { (hora: AjustesFondo.texto($0.0), dias: $0.1, que: $0.2) }
    }

    private var seccionAtajos: some View {
        Section {
            VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                Text("iOS no deja que una app cambie el fondo, pero Atajos sí. Una vez por cada hora de abajo:")
                paso(1, "En Atajos, ve a **Automatización** › **+** › **Hora del día**.")
                paso(2, "Pon la hora, elige los días y marca **Ejecutar inmediatamente**.")
                paso(3, "Añade la acción **Fondo de Tom ahora** (búscala por «Tom»).")
                paso(4, "Añade **Establecer fondo de pantalla**: elige **Pantalla de bloqueo** y el fondo que quieras cambiar, y desactiva **Mostrar vista previa** y **Recortar al sujeto**.")
            }
            .font(Tema.fuente(.texto))
            .padding(.vertical, Tema.Espacio.xs)

            ForEach(Array(automatizaciones.enumerated()), id: \.offset) { _, au in
                HStack {
                    Text(au.hora).font(Tema.fuente(.destacado)).monospacedDigit()
                        .frame(minWidth: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(au.que)
                        Text(au.dias).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Para que se ponga al día al marcar algo").font(Tema.fuente(.destacado))
                Text("Otra automatización: **App** › **Tom** › **Se cierra** › Ejecutar inmediatamente, con las mismas dos acciones.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            .padding(.vertical, Tema.Espacio.xs)

            VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                Text("Un fondo solo para Tom").font(Tema.fuente(.destacado))
                Text("En Ajustes › Fondo de pantalla › **Añadir nuevo fondo**, crea uno con cualquier foto. En «Establecer fondo de pantalla», toca el fondo y elige ese: tus otros fondos no se tocan. Si lo vinculas a un enfoque (mantén pulsado el bloqueo › **Enfoque**), Tom sale solo con ese enfoque.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
            .padding(.vertical, Tema.Espacio.xs)

            Button("Abrir Atajos", systemImage: "arrow.up.forward.app") {
                if let url = URL(string: "shortcuts://") { abrirURL(url) }
            }
        } header: {
            Text("Ponerlo solo con Atajos")
        } footer: {
            Text("Apple no deja compartir automatizaciones con un enlace, así que hay que crearlas a mano; es un minuto cada una. También está la acción «Fondo de Tom de un momento», que elige el momento sin mirar la hora. Si no quieres cambiar el fondo, el widget «Tom según la hora» hace lo mismo en la pantalla de bloqueo.")
        }
    }

    private func paso(_ n: Int, _ texto: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tema.Espacio.s) {
            Text("\(n)")
                .font(Tema.fuente(.pequeno, peso: .bold))
                .foregroundStyle(Tema.acentoTexto)
                .frame(width: 22, height: 22)
                .background(Tema.acento, in: Circle())
            Text(texto)
        }
    }

    // MARK: probar

    private var seccionProbar: some View {
        Section {
            Button {
                Task { await generaPrueba() }
            } label: {
                HStack {
                    Label("Generar el fondo de ahora", systemImage: "wand.and.stars")
                    if generando {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(generando)
            if let falloPrueba {
                Text(falloPrueba).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        } footer: {
            Text("Hace lo mismo que la acción de Atajos: lo puedes guardar en Fotos y ponerlo a mano.")
        }
    }

    private func generaPrueba() async {
        generando = true
        falloPrueba = nil
        defer { generando = false }
        ajustes.guarda()
        do {
            let r = try await GeneradorFondo.genera()
            guard let img = UIImage(data: r.datos) else { throw ErrorFondo(mensaje: "La imagen ha salido vacía.") }
            prueba = ImagenPrueba(imagen: img, datos: r.datos, momento: r.momento, segundos: r.segundos, pixeles: r.pixeles)
            Haptica.shared.toca(.marcar)
        } catch {
            falloPrueba = error.localizedDescription
            Haptica.shared.toca(.error)
        }
    }
}

private extension String {
    var capitalizedPrimera: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: el fondo generado

struct ImagenPrueba: Identifiable {
    let id = UUID()
    let imagen: UIImage
    let datos: Data
    let momento: MomentoFondo
    let segundos: Double
    let pixeles: CGSize
}

/// El fondo tal cual sale, para verlo y guardarlo en Fotos.
private struct HojaPrueba: View {
    let prueba: ImagenPrueba
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            VStack(spacing: Tema.Espacio.l) {
                Image(uiImage: prueba.imagen)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
                    .accessibilityLabel("Fondo de \(prueba.momento.nombre.lowercased()) generado")
                Text("\(prueba.momento.nombre) · \(Int(prueba.pixeles.width))×\(Int(prueba.pixeles.height)) · \(String(format: "%.2f", prueba.segundos).replacingOccurrences(of: ".", with: ",")) s")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                ShareLink(item: Image(uiImage: prueba.imagen),
                          preview: SharePreview("Fondo de Tom", image: Image(uiImage: prueba.imagen))) {
                    Label("Guardar o compartir", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Tema.acentoTexto)
            }
            .padding(Tema.Espacio.l)
            .background(Tema.fondo)
            .navigationTitle("Fondo de ahora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
    }
}

// MARK: elementos de un momento

/// Qué sale en un momento y en qué orden (arrastrar las asas para ordenar).
struct EditorElementos: View {
    let momento: MomentoFondo
    @Binding var ajustes: AjustesFondo

    private var lista: [ElementoVisible] { ajustes.elementos(momento) }

    var body: some View {
        List {
            Section {
                ForEach(lista) { e in
                    Toggle(isOn: Binding(get: { e.visible }, set: { v in
                        Haptica.shared.toca(.marcar)
                        var l = lista
                        if let i = l.firstIndex(where: { $0.elemento == e.elemento }) { l[i].visible = v }
                        ajustes.elementos[momento.rawValue] = l
                    })) {
                        Label(e.elemento.nombre, systemImage: e.elemento.simbolo)
                    }
                }
                .onMove { desde, hasta in
                    var l = lista
                    l.move(fromOffsets: desde, toOffset: hasta)
                    ajustes.elementos[momento.rawValue] = l
                }
            } footer: {
                Text("Arrastra las asas para cambiar el orden. Sale de arriba abajo.")
            }
            Section {
                Button("Volver a lo de siempre", systemImage: "arrow.uturn.backward") {
                    ajustes.elementos[momento.rawValue] = nil
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .navigationTitle(momento.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }
}
