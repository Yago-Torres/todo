import SwiftUI

/// El calendario del mes de la web (index.html → «Calendario»): un mapa de calor con los hábitos hechos (puntos de su
/// color) y los planificados (aro), mes a mes. Tocar un día abre ese día: marcar o desmarcar cada hábito y ponerlo o
/// quitarlo del plan. Marcar va por DatosNativos.marca y planificar por GestorHabitos.planea: los dos por la cola.
struct CalendarioHabitos: View {
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosNativos.shared
    @State private var mesAtras = 0
    @State private var elegido: DiaElegido?

    private let letras = ["L", "M", "X", "J", "V", "S", "D"]
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var primero: Date {
        let hoy = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: -mesAtras, to: hoy) ?? hoy
    }

    private var titulo: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        let t = f.string(from: primero)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Los días del mes con huecos delante para empezar en lunes (nil = hueco).
    private var casillas: [String?] {
        let hueco = (cal.component(.weekday, from: primero) + 5) % 7
        let n = cal.range(of: .day, in: .month, for: primero)?.count ?? 30
        return Array(repeating: nil, count: hueco) + (0..<n).map { k in
            Fecha.dia(cal.date(byAdding: .day, value: k, to: primero) ?? primero)
        }
    }

    var body: some View {
        let hoy = Fecha.hoy()
        let ids = Set(datos.habitos.map(\.id))
        let dias = casillas
        let marcas = dias.compactMap { $0 }.reduce(0) { $0 + (datos.log[$1]?.intersection(ids).count ?? 0) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tema.Espacio.m) {
                    HStack {
                        Button { withAnimation(Tema.Muelle.pantalla) { mesAtras += 1 } } label: {
                            Image(systemName: "chevron.left").frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Mes anterior")
                        Spacer()
                        VStack(spacing: 2) {
                            Text(titulo).font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto)
                                .contentTransition(.interpolate)
                            Text("\(marcas) marcas").font(Tema.fuente(.pequeno)).monospacedDigit().foregroundStyle(Tema.suave)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        Button { withAnimation(Tema.Muelle.pantalla) { mesAtras -= 1 } } label: {
                            Image(systemName: "chevron.right").frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Mes siguiente")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.acento)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(letras, id: \.self) { l in
                            Text(l).estiloEtiqueta().foregroundStyle(Tema.suave)
                        }
                        ForEach(Array(dias.enumerated()), id: \.offset) { _, dia in
                            if let dia { casilla(dia, hoy: hoy, ids: ids) } else { Color.clear.frame(height: 52) }
                        }
                    }
                    Text("Toca un día para marcar sus hábitos o planificarlos. Puntos llenos: hecho; aros: planificado.")
                        .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                }
                .padding(Tema.Espacio.l)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cierra() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Hoy") { withAnimation(Tema.Muelle.pantalla) { mesAtras = 0 } }.disabled(mesAtras == 0)
                }
            }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
        .presentationDragIndicator(.visible)
        .sheet(item: $elegido) { d in DiaHabitos(dia: d.id).presentationDetents([.medium, .large]) }
    }

    private func casilla(_ dia: String, hoy: String, ids: Set<String>) -> some View {
        let hechos = datos.habitos.filter { datos.log[dia]?.contains($0.id) ?? false }
        let planes = datos.habitos.filter { !(datos.log[dia]?.contains($0.id) ?? false) && (datos.plan[dia]?.contains($0.id) ?? false) }
        // intensidad 0-4 según la parte de los hábitos hecha ese día, como la web
        let nivel = ids.isEmpty || hechos.isEmpty ? 0 : min(4, Int((Double(hechos.count) / Double(ids.count) * 5).rounded(.up)))
        return Button {
            Haptica.shared.toca(.marcar)
            elegido = DiaElegido(id: dia)
        } label: {
            VStack(spacing: 3) {
                Text("\(Int(dia.suffix(2)) ?? 0)")
                    .font(Tema.fuente(.pequeno, peso: dia == hoy ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(nivel >= 3 ? Tema.acentoTexto : Tema.texto)
                HStack(spacing: 2) {
                    ForEach(hechos.prefix(4), id: \.id) { h in Circle().fill(Color(hex: h.c)).frame(width: 5, height: 5) }
                    ForEach(planes.prefix(max(0, 4 - hechos.count)), id: \.id) { h in
                        Circle().strokeBorder(Color(hex: h.c), lineWidth: 1).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(nivel == 0 ? Tema.carta : Tema.acento.opacity([0, 0.25, 0.45, 0.7, 0.95][nivel]),
                        in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
            .overlay {
                if dia == hoy {
                    RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous).strokeBorder(Tema.texto, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(EstiloHundir())
        .accessibilityLabel("\(FechaHabitos.larga(dia)): \(hechos.count) hechos, \(planes.count) planificados")
    }
}

private struct DiaElegido: Identifiable { let id: String }

enum FechaHabitos {
    /// «Jueves 12 de noviembre».
    static func larga(_ dia: String) -> String {
        guard let d = Fecha.fecha(dia) else { return dia }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d 'de' MMMM"
        let t = f.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// Un día del calendario: cada hábito con «hecho» (los días que ya han llegado) y «en el plan».
private struct DiaHabitos: View {
    let dia: String
    @Environment(\.dismiss) private var cierra
    @State private var datos = DatosNativos.shared
    @State private var planLocal: [String: Bool] = [:]
    @State private var error: String?

    var body: some View {
        let futuro = dia > Fecha.hoy()
        NavigationStack {
            List {
                Section {
                    ForEach(datos.habitos) { h in
                        let hecho = datos.log[dia]?.contains(h.id) ?? false
                        let plan = planLocal[h.id] ?? (datos.plan[dia]?.contains(h.id) ?? false)
                        HStack(spacing: Tema.Espacio.m) {
                            Circle().fill(Color(hex: h.c)).frame(width: 10, height: 10)
                            Text(h.n).font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                            Spacer()
                            Button {
                                planea(h.id, !plan)
                            } label: {
                                Image(systemName: plan ? "calendar.badge.checkmark" : "calendar.badge.plus")
                                    .foregroundStyle(plan ? Tema.acento : Tema.suave)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(plan ? "Quitar \(h.n) del plan" : "Planificar \(h.n)")
                            Button {
                                Haptica.shared.toca(hecho ? .desmarcar : .marcar)
                                Task { await datos.marca(h.id, hecho: !hecho, dia: dia) }
                            } label: {
                                Image(systemName: hecho ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(hecho ? Color(hex: h.c) : Tema.tenue)
                                    .frame(width: 36, height: 36)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.borderless)
                            .disabled(futuro)
                            .accessibilityLabel(hecho ? "\(h.n): hecho. Toca para desmarcar" : "\(h.n): sin hacer. Toca para marcar")
                        }
                        .listRowBackground(Tema.carta)
                    }
                } footer: {
                    Text(futuro ? "Aún no ha llegado: solo se puede planificar." : "El calendario de la izquierda planifica; el círculo marca hecho.")
                }
                if let error {
                    Text(error).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.peligro).listRowBackground(Tema.carta)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(FechaHabitos.larga(dia))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cierra() } } }
            .tint(Tema.acento)
        }
        .presentationBackground(Tema.fondo)
    }

    private func planea(_ id: String, _ si: Bool) {
        Haptica.shared.toca(si ? .marcar : .desmarcar)
        planLocal[id] = si
        Task {
            do {
                try await GestorHabitos.planea(id, dia: dia, si: si)
                error = nil
            } catch {
                planLocal[id] = nil
                Haptica.shared.toca(.error)
                self.error = error.localizedDescription
            }
        }
    }
}
