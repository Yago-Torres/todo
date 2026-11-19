import SwiftUI

/// Semana o día con franjas horarias: arriba lo de todo el día (y las tareas), debajo las 24 horas. Tocar un hueco crea
/// un evento a esa hora; mantener pulsado un evento y arrastrarlo lo cambia de hora (y de día, en la semana).
struct RejillaHorasCal: View {
    let dias: [String]
    let alTocarHueco: (String, String) -> Void
    let alTocarEvento: (EventoCal) -> Void
    let alTocarTarea: (TareaCal) -> Void

    @State private var datos = DatosCalendario.shared
    let alto: CGFloat = 48        // una hora
    let margen: CGFloat = 44      // la columna de las horas

    var body: some View {
        VStack(spacing: 0) {
            cabecera
            filaTodoElDia
            Divider().overlay(Tema.linea)
            ScrollViewReader { lector in
                ScrollView(.vertical) {
                    GeometryReader { geo in
                        let ancho = max(1, (geo.size.width - margen) / CGFloat(max(1, dias.count)))
                        ZStack(alignment: .topLeading) {
                            lineas(geo.size.width)
                            ForEach(dias.indices, id: \.self) { i in
                                columna(dias[i], ancho: ancho)
                                    .frame(width: ancho, height: alto * 24)
                                    .offset(x: margen + CGFloat(i) * ancho)
                            }
                            ahora(ancho: ancho)
                        }
                    }
                    .frame(height: alto * 24)
                    .id("rejilla")
                    // anclas para abrir a las 7
                    .overlay(alignment: .topLeading) {
                        Color.clear.frame(height: 1).offset(y: alto * 7).id("siete")
                    }
                }
                .contentMargins(.bottom, 110, for: .scrollContent)
                .onAppear { lector.scrollTo("siete", anchor: .top) }
            }
        }
    }

    // MARK: arriba

    private var cabecera: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: margen, height: 1)
            ForEach(dias, id: \.self) { d in
                let esHoy = d == datos.hoy
                VStack(spacing: 2) {
                    Text(UtilCal.titulo(d, "EEE")).estiloEtiqueta().foregroundStyle(Tema.suave)
                    Text(FechasES.texto(UtilCal.fecha(d), "d"))
                        .font(Tema.fuente(.destacado))
                        .foregroundStyle(esHoy ? Tema.acentoTexto : Tema.texto)
                        .frame(width: 30, height: 30)
                        .background(esHoy ? Tema.acento : Color.clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(UtilCal.cercano(d, hoy: datos.hoy))
            }
        }
        .padding(.vertical, Tema.Espacio.xs)
    }

    /// Los de todo el día, los que vienen de días anteriores y las tareas: en fichas pequeñas.
    private var filaTodoElDia: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("todo\nel día").font(.system(size: 9)).foregroundStyle(Tema.tenue)
                .multilineTextAlignment(.trailing)
                .frame(width: margen - 6, alignment: .trailing).padding(.trailing, 6)
            ForEach(dias, id: \.self) { d in
                VStack(spacing: 2) {
                    ForEach(datos.visibles.filter { $0.cubre(d) && ($0.todoElDia || $0.dia != d) }, id: \.clave) { e in
                        ficha(e.t, color: datos.color(e.cal)) { alTocarEvento(e) }
                    }
                    ForEach(datos.tareas.filter { $0.due == d }) { t in
                        ficha((t.hecha ? "✓ " : "") + (t.hora.isEmpty ? "" : t.hora + " ") + t.t, color: Tema.suave,
                              tachada: t.hecha) { alTocarTarea(t) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 1)
            }
        }
        .padding(.bottom, Tema.Espacio.xs)
    }

    private func ficha(_ texto: String, color: Color, tachada: Bool = false, toca: @escaping () -> Void) -> some View {
        Button(action: toca) {
            Text(texto)
                .font(.system(size: 10, weight: .semibold))
                .strikethrough(tachada)
                .lineLimit(1)
                .foregroundStyle(Tema.texto)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: las horas

    private func lineas(_ total: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { h in
            HStack(alignment: .top, spacing: 4) {
                Text(String(format: "%02d", h)).font(.system(size: 10).monospacedDigit()).foregroundStyle(Tema.tenue)
                    .frame(width: margen - 8, alignment: .trailing)
                    .offset(y: -6)
                Rectangle().fill(Tema.linea.opacity(0.6)).frame(height: 0.5)
            }
            .frame(width: total, height: alto, alignment: .topLeading)
            .offset(y: CGFloat(h) * alto)
        }
    }

    /// La raya de ahora, solo en la columna de hoy.
    @ViewBuilder private func ahora(ancho: CGFloat) -> some View {
        if let i = dias.firstIndex(of: datos.hoy) {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                let m = Calendar.current.component(.hour, from: ctx.date) * 60 + Calendar.current.component(.minute, from: ctx.date)
                Rectangle().fill(Tema.peligro).frame(width: ancho, height: 1.5)
                    .overlay(alignment: .leading) { Circle().fill(Tema.peligro).frame(width: 7, height: 7).offset(x: -3) }
                    .offset(x: margen + CGFloat(i) * ancho, y: CGFloat(m) / 60 * alto)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: una columna (un día)

    private struct Colocado: Identifiable {
        let evento: EventoCal
        let inicio: Int
        let fin: Int
        var columna: Int
        var columnas: Int
        var id: String { evento.clave }
    }

    /// Los que se pisan van uno al lado del otro.
    private func coloca(_ d: String) -> [Colocado] {
        let es = datos.visibles.filter { $0.dia == d && !$0.todoElDia }.compactMap { e -> Colocado? in
            guard let i = UtilCal.minutos(e.inicio) else { return nil }
            var f = UtilCal.minutos(e.fin) ?? (i + 60)
            if e.finDia > e.dia { f = 24 * 60 }   // sigue al día siguiente
            if f <= i { f = i + 60 }
            return Colocado(evento: e, inicio: i, fin: max(f, i + 20), columna: 0, columnas: 1)
        }.sorted { $0.inicio < $1.inicio }
        var out: [Colocado] = []
        var grupo: [Int] = []          // índices en `out` del grupo que se pisa
        var finGrupo = -1
        func cierra() {
            let n = (grupo.map { out[$0].columna }.max() ?? 0) + 1
            for j in grupo { out[j].columnas = n }
            grupo = []
        }
        for var c in es {
            if c.inicio >= finGrupo { cierra() }
            let ocupadas = Set(grupo.filter { out[$0].fin > c.inicio }.map { out[$0].columna })
            c.columna = (0...).first { !ocupadas.contains($0) } ?? 0
            out.append(c)
            grupo.append(out.count - 1)
            finGrupo = max(finGrupo, c.fin)
        }
        cierra()
        return out
    }

    private func columna(_ d: String, ancho: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in
                    let m = Int(p.y / alto * 2) * 30   // a la media hora
                    alTocarHueco(d, UtilCal.hhmm(m))
                }
                .accessibilityElement()
                .accessibilityLabel("\(UtilCal.cercano(d, hoy: datos.hoy)): crear un evento")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { alTocarHueco(d, "09:00") }
            ForEach(coloca(d)) { c in
                BloqueEventoCal(evento: c.evento, color: datos.color(c.evento.cal), alto: alto, anchoDia: ancho,
                                alTocar: { alTocarEvento(c.evento) },
                                alSoltar: { minutos, dias in mueve(c, minutos: minutos, dias: dias) })
                    .frame(width: max(8, ancho / CGFloat(c.columnas) - 2),
                           height: CGFloat(c.fin - c.inicio) / 60 * alto - 1)
                    .offset(x: CGFloat(c.columna) * ancho / CGFloat(c.columnas) + 1,
                            y: CGFloat(c.inicio) / 60 * alto)
            }
        }
    }

    private func mueve(_ c: Colocado, minutos: Int, dias: Int) {
        guard minutos != 0 || dias != 0, !c.evento.provisional else { return }
        let destino = UtilCal.suma(c.evento.dia, dias: self.dias.count > 1 ? dias : 0)
        let inicio = UtilCal.hhmm(max(0, min(23 * 60 + 45, c.inicio + minutos)))
        Task { await datos.mueve(c.evento, a: destino, inicio: inicio) }
    }
}

/// Un evento en la rejilla. Mantener pulsado y arrastrar: lo suelta a otra hora (de 15 en 15 min) o en otro día.
private struct BloqueEventoCal: View {
    let evento: EventoCal
    let color: Color
    let alto: CGFloat
    let anchoDia: CGFloat
    let alTocar: () -> Void
    let alSoltar: (Int, Int) -> Void

    @GestureState var arrastre: CGSize = .zero
    @State var levantado = false

    var body: some View {
        let pasos = { (t: CGSize) -> (Int, Int) in
            (Int((t.height / alto * 4).rounded()) * 15, Int((t.width / anchoDia).rounded()))
        }
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(evento.t).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                if let s = evento.sincro, s.falla {
                    Image(systemName: "exclamationmark.icloud").font(.system(size: 9)).foregroundStyle(Tema.aviso)
                }
            }
            Text(evento.inicio + (evento.fin.isEmpty ? "" : "–" + evento.fin))
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Tema.suave)
            if !evento.lugar.isEmpty {
                Text(evento.lugar).font(.system(size: 10)).foregroundStyle(Tema.suave).lineLimit(1)
            }
        }
        .foregroundStyle(Tema.texto)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
        .clipped()
        .opacity(evento.provisional ? 0.6 : 1)
        .scaleEffect(levantado ? 1.04 : 1)
        .shadow(color: .black.opacity(levantado ? 0.25 : 0), radius: 6, y: 3)
        .offset(arrastre)
        .zIndex(levantado ? 1 : 0)
        .onTapGesture(perform: alTocar)
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($arrastre) { valor, estado, _ in
                    if case .second(true, let d?) = valor { estado = d.translation }
                }
                .onChanged { valor in
                    if case .second(true, _) = valor, !levantado {
                        levantado = true
                        Haptica.shared.toca(.dia)
                    }
                }
                .onEnded { valor in
                    levantado = false
                    if case .second(true, let d?) = valor {
                        let (m, dd) = pasos(d.translation)
                        alSoltar(m, dd)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toca para cambiarlo. Mantén pulsado y arrastra para moverlo.")
    }
}
