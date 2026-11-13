import SwiftUI

/// Lo de arriba del modo «Presupuestos» (como la web): cuánto cobras al mes, qué día (los ciclos van de cobro a cobro),
/// cuánto dejan de ahorro los presupuestos y «Usar sugeridos». Se guarda al salir del campo o al elegir el día, por
/// la cola (sin red también; las cuentas del ciclo se recalculan cuando llega al servidor).
struct AjustesCicloGastos: View {
    let r: ResumenGastos
    @Binding var aviso: String?
    @State private var datos = DatosGastos.shared
    @State private var ingreso = ""
    @State private var nota: String?
    @FocusState private var foco: Bool

    private var a: EstadoGastos.Ajustes { datos.ajustes }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espacio.s) {
            HStack(spacing: Tema.Espacio.s) {
                Text("Cobras al mes").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Spacer()
                TextField("vacío si varía", text: $ingreso)
                    .keyboardType(.decimalPad)
                    .focused($foco)
                    .multilineTextAlignment(.trailing)
                    .font(Tema.fuente(.texto)).monospacedDigit()
                    .padding(.horizontal, Tema.Espacio.m).padding(.vertical, 8)
                    .frame(width: 130)
                    .background(Tema.carta2, in: RoundedRectangle(cornerRadius: Tema.Radio.boton, style: .continuous))
                    .accessibilityLabel("Lo que cobras al mes, en euros")
                Text("€").font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
            }
            HStack(spacing: Tema.Espacio.s) {
                Text("Día de cobro").font(Tema.fuente(.texto)).foregroundStyle(Tema.texto)
                Spacer()
                Picker("Día de cobro", selection: Binding(get: { a.diaCobro }, set: { ponDia($0) })) {
                    ForEach(1...31, id: \.self) { Text("El \($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Tema.acento)
            }
            Text(resumen).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
            if let nota {
                Text(nota).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.aviso)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Usar sugeridos") {
                Haptica.shared.toca(.marcar)
                Task {
                    do { try await datos.usaSugeridos(); aviso = nil }
                    catch { Haptica.shared.toca(.error); aviso = DatosGastos.mensaje(error) }
                }
            }
            .font(Tema.fuente(.pequeno, peso: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Tema.acentoSuave, in: Capsule())
            .foregroundStyle(Tema.acento)
        }
        .onAppear { ingreso = campo(a.ingreso) }
        .onChange(of: a.ingreso) { _, v in if !foco { ingreso = campo(v) } }
        .onChange(of: foco) { _, ahora in if !ahora { guardaIngreso() } }
    }

    private func campo(_ x: Double) -> String { x > 0 ? Eur.campo(x).replacingOccurrences(of: ",00", with: "") : "" }

    /// Lo mismo que dice la web debajo de los ajustes.
    private var resumen: String {
        let presu = (datos.estado?.cats.map(\.presu) ?? r.cats.map(\.presu)).reduce(0, +)
        if a.ingreso <= 0 {
            return presu > 0 ? "Presupuesto \(Eur.entero(presu)) al ciclo."
                             : "Los sugeridos son lo que gastas de media: \(Eur.entero(r.sugeridoTotal)) al ciclo."
        }
        if presu > 0 {
            let ahorro = a.ingreso - presu - a.hucha
            return "Presupuesto \(Eur.entero(presu)) · ahorro objetivo \(Eur.entero(ahorro)) (\(Int((ahorro * 100 / a.ingreso).rounded())) %)"
        }
        return "Los sugeridos dejan \(Eur.entero(a.ingreso - r.sugeridoTotal)) de ahorro al ciclo."
    }

    private func guardaIngreso() {
        let nuevo = ingreso.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : (Eur.lee(ingreso) ?? a.ingreso)
        guard abs(nuevo - a.ingreso) > 0.004 else { ingreso = campo(a.ingreso); return }
        guarda(["ingreso": max(0, nuevo)], nuevo > 0 ? "Ingreso: \(Eur.entero(nuevo)) al mes" : "Ingreso variable")
    }

    private func ponDia(_ d: Int) {
        guard d != a.diaCobro else { return }
        guarda(["dia_cobro": min(31, max(1, d))], "Día de cobro: el \(d)")
    }

    private func guarda(_ cambios: [String: Any], _ texto: String) {
        Task {
            do {
                let enCola = try await datos.ponAjustes(cambios, resumen: texto)
                Haptica.shared.toca(.marcar)
                aviso = nil
                withAnimation(Tema.Muelle.pantalla) {
                    nota = enCola ? "Guardado en el iPhone. Las cuentas del ciclo se recalculan al volver la conexión." : nil
                }
            } catch {
                Haptica.shared.toca(.error)
                ingreso = campo(a.ingreso)
                aviso = DatosGastos.mensaje(error)
            }
        }
    }
}
