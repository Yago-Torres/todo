import SwiftUI

/// Calendario (lo de static/calendario.html): eventos propios (se copian a Google y a iCloud desde la Pi), tareas con
/// fecha y recordatorios de Pendientes. Vistas Mes, Semana, Día y Agenda; «+» crea (mantén pulsado para elegir qué).
struct PantallaCalendario: View {
    @State private var datos = DatosCalendario.shared
    @AppStorage("calendarioVista") private var vistaGuardada = VistaCal.mes.rawValue
    @State private var dia = UtilCal.hoy()
    @State private var hoja: HojaEventoCal.Modo?

    private var vista: VistaCal { VistaCal(rawValue: vistaGuardada) ?? .mes }
    private var vistaBinding: Binding<VistaCal> {
        Binding(get: { vista }, set: { v in withAnimation(Tema.Muelle.pantalla) { vistaGuardada = v.rawValue } })
    }

    /// Lo que se ve ahora: lo que hay que tener cargado.
    private var rango: (String, String) {
        switch vista {
        case .mes:
            let r = UtilCal.rejillaMes(dia)
            return (r.first ?? dia, r.last ?? dia)
        case .semana:
            let l = UtilCal.lunes(dia)
            return (l, UtilCal.suma(l, dias: 6))
        case .dia: return (dia, dia)
        case .agenda: return (datos.hoy, UtilCal.suma(datos.hoy, dias: 60))
        }
    }

    var body: some View {
        VStack(spacing: Tema.Espacio.s) {
            cabecera
            SelectorPildoras(opciones: VistaCal.allCases.map { (valor: $0, titulo: $0.nombre) }, seleccion: vistaBinding)
            if vista != .agenda { navegacion }
            contenido
        }
        .padding(.top, Tema.Espacio.s)
        .environment(\.locale, FechasES.locale)
        .tostada(datos.aviso) { datos.quitaAviso() }
        .task(id: "\(rango.0)|\(rango.1)") { await datos.asegura(rango.0, rango.1) }
        .sheet(item: $hoja) { m in HojaEventoCal(modo: m) }
    }

    // MARK: cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UtilCal.titulo(datos.hoy, "EEEE d 'de' MMMM")).estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text("Calendario").font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                }
                Spacer()
                if dia != datos.hoy {
                    Button("Hoy") { withAnimation(Tema.Muelle.pantalla) { dia = datos.hoy } }
                        .font(Tema.fuente(.pequeno, peso: .semibold))
                        .foregroundStyle(Tema.texto)
                        .padding(.horizontal, Tema.Espacio.m).frame(height: 32)
                        .background(Tema.carta2, in: Capsule())
                }
                Menu {
                    ForEach(TipoElementoCal.allCases) { t in
                        Button { nuevo(t) } label: {
                            Label(t.nombre, systemImage: t == .evento ? "calendar.badge.plus" : t == .tarea ? "checklist" : "bell")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.acentoTexto)
                        .frame(width: 40, height: 40)
                        .background(Tema.acento, in: Circle())
                } primaryAction: {
                    nuevo(.evento)
                }
                .accessibilityLabel("Nuevo evento")
                .accessibilityHint("Mantén pulsado para elegir tarea o recordatorio")
            }
            if let copia = datos.copia {
                Label(API.notaCopia(copia), systemImage: "wifi.slash")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
            } else if let e = datos.error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro)
            }
        }
        .padding(.horizontal, Tema.Espacio.l)
    }

    private func nuevo(_ t: TipoElementoCal) {
        hoja = .nuevo(dia: dia, hora: nil, tipo: t)
    }

    private var navegacion: some View {
        HStack {
            Button { pasa(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .accessibilityLabel("Anterior")
            Spacer()
            Text(tituloNavegacion)
                .font(Tema.fuente(.seccion)).foregroundStyle(Tema.texto)
                .contentTransition(.numericText())
            Spacer()
            Button { pasa(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .accessibilityLabel("Siguiente")
        }
        .foregroundStyle(Tema.texto)
        .padding(.horizontal, Tema.Espacio.l)
    }

    private var tituloNavegacion: String {
        switch vista {
        case .mes, .agenda: return UtilCal.titulo(dia, "LLLL yyyy")
        case .semana:
            let l = UtilCal.lunes(dia), d = UtilCal.suma(l, dias: 6)
            return FechasES.texto(UtilCal.fecha(l), "d MMM") + " – " + FechasES.texto(UtilCal.fecha(d), "d MMM")
        case .dia: return UtilCal.cercano(dia, hoy: datos.hoy)
        }
    }

    private func pasa(_ n: Int) {
        withAnimation(Tema.Muelle.pantalla) {
            switch vista {
            case .mes, .agenda: dia = UtilCal.suma(UtilCal.inicioMes(dia), meses: n)
            case .semana: dia = UtilCal.suma(dia, dias: 7 * n)
            case .dia: dia = UtilCal.suma(dia, dias: n)
            }
        }
        Haptica.shared.toca(.dia)
    }

    @ViewBuilder private var contenido: some View {
        switch vista {
        case .mes: mes
        case .semana, .dia:
            RejillaHorasCal(dias: vista == .dia ? [dia] : UtilCal.dias(desde: UtilCal.lunes(dia), 7),
                            alTocarHueco: { d, h in dia = d; hoja = .nuevo(dia: d, hora: h, tipo: .evento) },
                            alTocarEvento: { e in abre(e) },
                            alTocarTarea: { t in Task { await datos.marca(t, hecha: !t.hecha) } })
        case .agenda: agenda
        }
    }

    // MARK: mes

    private var mes: some View {
        ScrollView {
            VStack(spacing: Tema.Espacio.m) {
                let rejilla = UtilCal.rejillaMes(dia)
                let mesActual = String(dia.prefix(7))
                VStack(spacing: Tema.Espacio.xs) {
                    HStack(spacing: 0) {
                        ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { l in
                            Text(l).estiloEtiqueta().foregroundStyle(Tema.tenue).frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                        ForEach(rejilla, id: \.self) { d in
                            celda(d, delMes: d.hasPrefix(mesActual))
                        }
                    }
                }
                .carta(relleno: Tema.Espacio.s)
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                    if abs(v.translation.width) > abs(v.translation.height) { pasa(v.translation.width < 0 ? 1 : -1) }
                })
                agendaDia(dia)
            }
            .padding(.horizontal, Tema.Espacio.l)
        }
        .contentMargins(.bottom, 110, for: .scrollContent)
        .refreshable { await datos.recarga() }
    }

    private func celda(_ d: String, delMes: Bool) -> some View {
        let esHoy = d == datos.hoy, elegido = d == dia
        return Button {
            withAnimation(Tema.Muelle.toque) { dia = d }
        } label: {
            VStack(spacing: 3) {
                Text(FechasES.texto(UtilCal.fecha(d), "d"))
                    .font(Tema.fuente(.texto, peso: esHoy || elegido ? .bold : .regular))
                    .foregroundStyle(esHoy ? Tema.acentoTexto : delMes ? Tema.texto : Tema.tenue)
                    .frame(width: 30, height: 30)
                    .background(esHoy ? Tema.acento : Color.clear, in: Circle())
                let puntos = datos.puntos(d)
                HStack(spacing: 2) {
                    ForEach(puntos.indices, id: \.self) { i in
                        Circle().fill(puntos[i]).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(elegido ? Tema.acentoSuave : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UtilCal.cercano(d, hoy: datos.hoy) + (datos.elementos(d).isEmpty ? "" : ", \(datos.elementos(d).count) cosas"))
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    private func agendaDia(_ d: String) -> some View {
        let lista = datos.elementos(d)
        return VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack {
                Text(UtilCal.cercano(d, hoy: datos.hoy)).estiloEtiqueta().foregroundStyle(Tema.suave)
                Spacer()
                Button { nuevo(.evento) } label: { Label("Añadir", systemImage: "plus") }
                    .font(Tema.fuente(.pequeno, peso: .semibold)).foregroundStyle(Tema.acento)
            }
            if lista.isEmpty {
                Text("Nada este día.").font(Tema.fuente(.texto)).foregroundStyle(Tema.tenue)
                    .padding(.vertical, Tema.Espacio.s)
            } else {
                ForEach(lista) { el in fila(el, dia: d) }
            }
        }
        .carta(relleno: Tema.Espacio.m)
    }

    // MARK: agenda

    private var agenda: some View {
        let dias = UtilCal.dias(desde: datos.hoy, 61).filter { !datos.elementos($0).isEmpty }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Tema.Espacio.m) {
                if dias.isEmpty && !datos.cargando {
                    VStack(spacing: Tema.Espacio.s) {
                        Image(systemName: "calendar").font(.system(size: 34)).foregroundStyle(Tema.tenue)
                        Text("Nada en los próximos dos meses. Con «+» apuntas un evento, una tarea o un recordatorio.")
                            .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(Tema.Espacio.xl)
                }
                ForEach(dias, id: \.self) { d in
                    VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                        Text(UtilCal.cercano(d, hoy: datos.hoy)).estiloEtiqueta()
                            .foregroundStyle(d == datos.hoy ? Tema.acento : Tema.suave)
                        ForEach(datos.elementos(d)) { el in fila(el, dia: d) }
                    }
                    .carta(relleno: Tema.Espacio.m)
                }
            }
            .padding(.horizontal, Tema.Espacio.l)
        }
        .contentMargins(.bottom, 110, for: .scrollContent)
        .refreshable { await datos.recarga() }
    }

    /// Los entrenos los pone el plan: se cambian en Entreno y el calendario los sigue solo.
    private func abre(_ e: EventoCal) {
        if e.entreno.isEmpty { hoja = .edita(e) } else { Navegador.shared.abre("/entreno.html") }
    }

    // MARK: una fila

    @ViewBuilder private func fila(_ el: ElementoDiaCal, dia d: String) -> some View {
        switch el {
        case .evento(let e):
            Button { abre(e) } label: {
                HStack(alignment: .top, spacing: Tema.Espacio.s) {
                    RoundedRectangle(cornerRadius: 2).fill(datos.color(e.cal)).frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(e.t).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                                .multilineTextAlignment(.leading)
                            if !e.entreno.isEmpty {
                                Image(systemName: "dumbbell").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                                    .accessibilityLabel("Del plan de Entreno")
                            }
                            if !e.repite.isEmpty {
                                Image(systemName: "repeat").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                            }
                        }
                        Text(horario(e, d)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        if !e.lugar.isEmpty {
                            Label(e.lugar, systemImage: "mappin").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        }
                    }
                    Spacer(minLength: 0)
                    if let s = e.sincro, s.falla {
                        Image(systemName: "exclamationmark.icloud").foregroundStyle(Tema.aviso)
                            .accessibilityLabel("No se ha copiado: \(s.detalle)")
                    } else if e.provisional || (e.sincro?.pendiente ?? false) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                            .accessibilityLabel("Copiándose a tus calendarios")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if e.entreno.isEmpty {
                    Button { hoja = .edita(e) } label: { Label("Cambiar", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await datos.borraEvento(e) } } label: {
                        Label(e.repite.isEmpty ? "Borrar" : "Borrar la serie", systemImage: "trash")
                    }
                } else {
                    Button { abre(e) } label: { Label("Cambiar en Entreno", systemImage: "dumbbell") }
                }
            }
        case .tarea(let t):
            HStack(alignment: .top, spacing: Tema.Espacio.s) {
                Button { Task { await datos.marca(t, hecha: !t.hecha) } } label: {
                    Image(systemName: t.hecha ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(t.hecha ? Tema.acento : Tema.suave)
                }
                .buttonStyle(.plain)
                .disabled(t.provisional)
                .accessibilityLabel(t.hecha ? "Desmarcar \(t.t)" : "Marcar hecha: \(t.t)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.t).font(Tema.fuente(.texto)).foregroundStyle(t.hecha ? Tema.tenue : Tema.texto)
                        .strikethrough(t.hecha)
                    Label(t.hora.isEmpty ? "Tarea" : "Recordatorio · \(t.hora)",
                          systemImage: t.hora.isEmpty ? "checklist" : "bell")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { Navegador.shared.abre("/pendientes.html") }
        }
    }

    private func horario(_ e: EventoCal, _ d: String) -> String {
        if e.todoElDia {
            return e.finDia > e.dia ? "Todo el día · hasta el \(FechasES.texto(UtilCal.fecha(e.finDia), "d MMM"))" : "Todo el día"
        }
        if e.dia != d { return "Sigue desde el \(FechasES.texto(UtilCal.fecha(e.dia), "d MMM"))" }
        return e.inicio + (e.fin.isEmpty ? "" : " – " + e.fin)
    }
}
