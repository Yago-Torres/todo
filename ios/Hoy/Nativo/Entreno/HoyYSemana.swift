import SwiftUI

/// Lo que toca hoy: una ficha por hábito de entreno (su rutina, Empezar/Seguir, Hecho), lo que se pasó estos días y
/// entrenar otra rutina.
struct TarjetaHoyEntreno: View {
    @Binding var viendo: VistaRutina.Ver?
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        let hoy = datos.hoy
        let ids = e.entrenoDe(hoy)
        let atras = e.atrasados(hoy: hoy)
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt(titulo: "Hoy") {
                Text(FormatoEnt.diaSemana(hoy)).estiloEtiqueta().foregroundStyle(Tema.suave)
            }
            if ids.isEmpty {
                Text("Hoy no toca entrenar. Si vas igual, elige abajo la rutina.")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            ForEach(ids, id: \.self) { id in
                if let h = e.habito(id) {
                    FichaEntreno(dia: hoy, habito: h, rutina: e.rutinaDe(hoy, id), viendo: $viendo)
                }
            }
            if !atras.isEmpty {
                VStack(alignment: .leading, spacing: Tema.Espacio.s) {
                    Text("Se te pasó").estiloEtiqueta().foregroundStyle(Tema.suave)
                    ForEach(atras, id: \.h) { x in
                        HStack {
                            Text(e.rutinaDe(x.dia, x.h)?.n ?? e.habito(x.h)?.n ?? x.h)
                                .font(Tema.fuente(.texto)).foregroundStyle(Tema.texto).lineLimit(1)
                            Text("· \(FormatoEnt.diaSemana(x.dia))").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                            Spacer()
                            Button("Hacer hoy") {
                                Haptica.shared.toca(.marcar)
                                withAnimation(Tema.Muelle.toque) { datos.cambia { $0.mueve(x.h, de: x.dia, a: hoy) } }
                            }
                            .buttonStyle(BotonMini())
                        }
                    }
                }
                .padding(.top, Tema.Espacio.xs)
            }
            let pesas = e.rutinas.filter { $0.tipo == "pesas" }
            if !pesas.isEmpty {
                Menu {
                    ForEach(pesas) { r in
                        Button(r.n) { SesionEnCurso.shared.empieza(r) }
                    }
                } label: {
                    Label("Entrenar otra rutina", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(BotonEnt())
            }
        }
        .carta()
    }
}

/// Un hábito de entreno de un día con su rutina.
struct FichaEntreno: View {
    let dia: String
    let habito: HabitoGym
    let rutina: RutinaGym?
    @Binding var viendo: VistaRutina.Ver?
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        let hecho = e.hecho(dia, habito.id)
        let delDia = e.gym[dia] ?? []
        let viva = rutina.flatMap { r in r.tipo == "pesas" ? delDia.first { $0.rutina == r.id && !$0.fin } : nil }
        let acabada = rutina.flatMap { r in r.tipo == "pesas" ? delDia.last { $0.rutina == r.id && $0.fin } : nil }
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Circle().fill(Color(hex: habito.c)).frame(width: 8, height: 8)
                Text(habito.n).font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.suave)
                Spacer()
                if viva != nil { ChipEnt(texto: "a medias", color: Tema.aviso, fondo: Tema.carta) }
                if hecho { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.acento) }
            }
            if let r = rutina {
                Text(r.n).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Text(subtitulo(r, acabada)).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave).monospacedDigit()
                HStack(spacing: Tema.Espacio.s) {
                    switch r.tipo {
                    case "pesas":
                        Button(viva != nil ? "Seguir" : acabada != nil ? "Otra vez" : "Empezar") {
                            Haptica.shared.toca(.marcar)
                            SesionEnCurso.shared.empieza(r)
                        }
                        .buttonStyle(BotonEnt(principal: !hecho))
                    case "movilidad":
                        Button("Empezar") { GuiaEnCurso.shared.empieza(r) }
                            .buttonStyle(BotonEnt(principal: !hecho))
                    default:
                        Button("Ver la sesión") { viendo = .init(dia: dia, habito: habito.id, rutina: r.id) }
                            .buttonStyle(BotonEnt())
                    }
                    Button(hecho ? "Desmarcar" : "Hecho") {
                        Haptica.shared.toca(hecho ? .desmarcar : .marcar)
                        withAnimation(Tema.Muelle.toque) { datos.marca(habito.id, dia: dia, !hecho) }
                    }
                    .buttonStyle(BotonEnt())
                }
            } else {
                Text("Sin rutina asignada").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                Menu {
                    ForEach(e.rutinas.filter { $0.hab.isEmpty || $0.hab == habito.id }) { r in
                        Button(r.n) { datos.cambia { $0.asigna(habito.id, dia: dia, rutina: r.id) } }
                    }
                } label: {
                    Text("Elegir rutina").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(BotonEnt(principal: true))
            }
        }
        .padding(Tema.Espacio.m)
        .background(hecho ? Tema.acentoSuave : Tema.carta2,
                    in: RoundedRectangle(cornerRadius: Tema.Radio.carta, style: .continuous))
        .animation(Tema.Muelle.toque, value: hecho)
    }

    private func subtitulo(_ r: RutinaGym, _ acabada: SesionGym?) -> String {
        let n = r.bloques.count
        if r.tipo == "movilidad" { return "\(n) pasos · \(Int((Double(r.duracion) / 60).rounded())) min" }
        if let acabada { return acabada.resumen }
        return "\(n) \(n == 1 ? "ejercicio" : "ejercicios")"
    }
}

/// La semana planificada: lunes a domingo con lo que toca entrenar cada día. Mover a otro día (con su sesión),
/// planificar y quitar; tocar una sesión enseña sus ejercicios.
struct TarjetaSemana: View {
    @Binding var viendo: VistaRutina.Ver?
    @State private var datos = DatosEntreno.shared
    @State private var semana = 0

    var body: some View {
        let hoy = datos.hoy
        let lunes = FormatoEnt.mas(FormatoEnt.lunes(hoy), 7 * semana)
        let dias = (0..<7).map { FormatoEnt.mas(lunes, $0) }
        VStack(alignment: .leading, spacing: Tema.Espacio.m) {
            TituloEnt(titulo: semana == 0 ? "Esta semana" : semana == 1 ? "La semana que viene"
                      : semana == -1 ? "La semana pasada" : "Semana del \(FormatoEnt.corta(lunes))") {
                HStack(spacing: Tema.Espacio.m) {
                    Button { withAnimation(Tema.Muelle.pantalla) { semana -= 1 } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Semana anterior")
                    Button { withAnimation(Tema.Muelle.pantalla) { semana += 1 } } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Semana siguiente")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tema.acento)
            }
            VStack(spacing: 0) {
                ForEach(dias, id: \.self) { d in
                    DiaSemanaEnt(dia: d, hoy: hoy, viendo: $viendo)
                    if d != dias.last { Divider().overlay(Tema.linea) }
                }
            }
            Text("Mantén pulsada una sesión para moverla a otro día o quitarla.")
                .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
        }
        .carta()
    }
}

struct DiaSemanaEnt: View {
    let dia: String
    let hoy: String
    @Binding var viendo: VistaRutina.Ver?
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        let ids = e.entrenoDe(dia)
        HStack(alignment: .top, spacing: Tema.Espacio.m) {
            VStack(spacing: 0) {
                Text(FormatoEnt.letra(dia)).estiloEtiqueta()
                Text(String(Int(dia.suffix(2)) ?? 0)).font(Tema.fuente(.destacado)).monospacedDigit()
            }
            .foregroundStyle(dia == hoy ? Tema.acento : dia < hoy ? Tema.tenue : Tema.texto)
            .frame(width: 34)
            VStack(alignment: .leading, spacing: Tema.Espacio.xs) {
                if ids.isEmpty {
                    Text("Descanso").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
                        .frame(minHeight: 30)
                }
                ForEach(ids, id: \.self) { h in
                    sesion(h, e)
                }
            }
            Spacer(minLength: 0)
            planificar(e)
        }
        .padding(.vertical, Tema.Espacio.s)
    }

    private func sesion(_ h: String, _ e: EstadoEntreno) -> some View {
        let hab = e.habito(h)
        let r = e.rutinaDe(dia, h)
        let hecho = e.hecho(dia, h)
        return Button {
            if let r { viendo = .init(dia: dia, habito: h, rutina: r.id) }
        } label: {
            HStack(spacing: Tema.Espacio.s) {
                Circle().fill(Color(hex: hab?.c ?? "#888888")).frame(width: 8, height: 8)
                Text(r?.n ?? hab?.n ?? h)
                    .font(Tema.fuente(.texto, peso: .medium))
                    .foregroundStyle(hecho ? Tema.suave : Tema.texto)
                    .strikethrough(hecho, color: Tema.tenue)
                    .lineLimit(1)
                if hecho {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.acento)
                } else if dia < hoy {
                    Text("pendiente").font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                }
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Mover a…") {
                ForEach(destinos, id: \.self) { a in
                    Button(FormatoEnt.diaSemana(a) + (a == hoy ? " (hoy)" : "")) {
                        Haptica.shared.toca(.marcar)
                        withAnimation(Tema.Muelle.pantalla) { datos.cambia { $0.mueve(h, de: dia, a: a) } }
                    }
                }
            }
            Menu("Cambiar la rutina") {
                ForEach(e.rutinas.filter { $0.hab.isEmpty || $0.hab == h }) { x in
                    Button(x.n) { datos.cambia { $0.asigna(h, dia: dia, rutina: x.id) } }
                }
            }
            Button(hecho ? "Desmarcar" : "Marcar como hecho", systemImage: hecho ? "arrow.uturn.backward" : "checkmark") {
                withAnimation(Tema.Muelle.toque) { datos.marca(h, dia: dia, !hecho) }
            }
            Button("Quitar de este día", systemImage: "trash", role: .destructive) {
                withAnimation(Tema.Muelle.pantalla) { datos.cambia { $0.quitaDelPlan(h, dia: dia) } }
            }
        }
        .accessibilityHint("Mantén pulsado para moverla, cambiar la rutina o quitarla")
    }

    /// Los otros días de esa semana y la siguiente.
    private var destinos: [String] {
        let lunes = FormatoEnt.lunes(dia)
        return (0..<14).map { FormatoEnt.mas(lunes, $0) }.filter { $0 != dia }
    }

    private func planificar(_ e: EstadoEntreno) -> some View {
        Menu {
            ForEach(e.habitosDeEntreno) { h in
                let rutinas = e.rutinas.filter { $0.hab == h.id }
                if rutinas.count <= 1 {
                    Button(h.n) { datos.cambia { $0.planifica(h.id, dia: dia, rutina: rutinas.first?.id) } }
                } else {
                    Menu(h.n) {
                        ForEach(rutinas) { r in
                            Button(r.n) { datos.cambia { $0.planifica(h.id, dia: dia, rutina: r.id) } }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 18))
                .foregroundStyle(Tema.acento)
                .frame(width: 36, height: 30)
        }
        .accessibilityLabel("Planificar un entreno el \(FormatoEnt.larga(dia))")
    }
}

/// Una rutina por dentro: sus ejercicios con series, repes, kilos y notas (y el monigote). Si es de hoy y de pesas
/// o guiada, se puede empezar desde aquí.
struct VistaRutina: View {
    struct Ver: Identifiable, Hashable {
        var dia: String
        var habito: String?
        var rutina: String
        var id: String { "\(dia)|\(habito ?? "")|\(rutina)" }
    }

    let ver: Ver
    let cierra: () -> Void
    @State private var datos = DatosEntreno.shared

    var body: some View {
        let e = datos.e
        ScrollView {
            if let r = e.rutina(ver.rutina) {
                VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    Text(FormatoEnt.larga(ver.dia)).estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text(r.n).font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                    if ver.dia == datos.hoy && (r.tipo == "pesas" || r.tipo == "movilidad") {
                        Button(r.tipo == "pesas" ? "Empezar la sesión" : "Empezar la rutina") {
                            cierra()
                            if r.tipo == "pesas" { SesionEnCurso.shared.empieza(r) } else { GuiaEnCurso.shared.empieza(r) }
                        }
                        .buttonStyle(BotonEnt(principal: true, alto: 50))
                    }
                    ForEach(Array(r.bloques.enumerated()), id: \.offset) { _, b in
                        FilaBloque(b: b, tipo: r.tipo)
                    }
                }
                .padding(Tema.Espacio.l)
            } else {
                Text("Esa rutina ya no existe.").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave).padding()
            }
        }
        .background(Tema.fondo.ignoresSafeArea())
    }
}

struct FilaBloque: View {
    let b: BloqueGym
    let tipo: String

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espacio.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(b.ej).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                Text(medida).font(Tema.fuente(.pequeno, peso: .medium)).foregroundStyle(Tema.acento).monospacedDigit()
                if !b.nota.isEmpty {
                    Text(b.nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let m = MonigoteDatos.de(b.ej) {
                Monigote(datos: m).frame(width: 84)
            }
        }
        .carta(relleno: Tema.Espacio.m)
    }

    private var medida: String {
        if tipo == "movilidad" || tipo == "carrera" {
            return b.seg > 0 ? (b.seg >= 120 ? "\(b.seg / 60) min" : "\(b.seg) s") : (b.repes.isEmpty ? "" : b.repes)
        }
        var partes = ["\(b.series)×\(b.repes.isEmpty ? (b.porTiempo ? "\(b.seg) s" : "–") : b.repes)"]
        if b.kg > 0 { partes.append("\(FormatoEnt.num(b.kg)) kg") }
        return partes.joined(separator: " · ")
    }
}
