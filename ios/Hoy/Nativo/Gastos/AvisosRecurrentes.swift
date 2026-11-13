import SwiftUI
import UserNotifications

/// Aviso local el día antes de cada cargo recurrente previsto («Mañana se cobra Netflix: 12,99 €»), a las 10:00.
/// Opcional y por instancia (Configurar → Gastos recurrentes): lo de Aitana solo avisa si se pide. Van con su propio
/// prefijo, así que Avisos.programa (que rehace los «hoy.…») no los toca. Se reprograman cada vez que llega el resumen.
enum AvisosRecurrentes {
    static let claveYago = "gastos.avisoRecurrentes"
    static let claveAitana = "gastos.avisoRecurrentesAitana"
    /// Como mucho tantos por instancia: iOS guarda 64 pendientes entre todos los avisos de Tom.
    private static let maximo = 4

    static func activos(_ inst: InstanciaGastos) -> Bool {
        Almacen.defaults.bool(forKey: inst == .yago ? claveYago : claveAitana)
    }

    private static func prefijo(_ inst: InstanciaGastos) -> String { "gastos.\(inst.rawValue).recurrente." }

    static func programa(_ inst: InstanciaGastos, _ lista: [Recurrente]) {
        let activos = activos(inst), pre = prefijo(inst)
        let cal = Calendar.current
        // lo que hay que programar se calcula ya (las fechas), y se manda en segundo plano
        var nuevos: [UNNotificationRequest] = []
        if activos {
            for r in lista.filter({ $0.estado != "no" }).sorted(by: { $0.proximo < $1.proximo }) {
                guard nuevos.count < maximo, let prox = FechaGasto.fecha(r.proximo),
                      let antes = cal.date(byAdding: .day, value: -1, to: prox),
                      let cuando = cal.date(bySettingHour: 10, minute: 0, second: 0, of: antes), cuando > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = "Mañana se cobra \(r.n)"
                c.body = "\(Eur.texto(r.importe)), \(r.periodo)" + (inst == .aitana ? ". Gastos de Aitana." : ".")
                c.sound = .default
                c.threadIdentifier = "gastos.recurrentes"
                c.userInfo = ["ruta": "/gastos.html"]
                let disparo = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando), repeats: false)
                nuevos.append(UNNotificationRequest(identifier: pre + r.clave + "." + r.proximo, content: c, trigger: disparo))
            }
        }
        let programar = nuevos
        Task.detached {
            let centro = UNUserNotificationCenter.current()
            let viejos = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(pre) }
            centro.removePendingNotificationRequests(withIdentifiers: viejos)
            for n in programar { try? await centro.add(n) }
        }
    }

    /// Al cambiar el interruptor: pide los recurrentes de ahora (o la copia) y vuelve a programar.
    @MainActor
    static func reprograma(_ inst: InstanciaGastos) async {
        guard activos(inst) else { programa(inst, []); return }
        _ = await Avisos.pidePermiso()
        guard let r = try? await API.leeOCopia("\(inst.base)/resumen"),
              let resumen = try? JSONDecoder().decode(ResumenGastos.self, from: r.datos) else { return }
        programa(inst, resumen.recurrentes)
    }
}

/// Configurar → Gastos recurrentes.
struct SeccionAvisosRecurrentes: View {
    @AppStorage(AvisosRecurrentes.claveYago, store: Almacen.defaults) private var yago = false
    @AppStorage(AvisosRecurrentes.claveAitana, store: Almacen.defaults) private var aitana = false

    var body: some View {
        Section {
            Toggle("Avisar el día antes de un cargo", isOn: $yago)
            Toggle("También los de Aitana", isOn: $aitana)
        } header: {
            Text("Gastos recurrentes")
        } footer: {
            Text("A las 10:00 del día antes: «Mañana se cobra Netflix: 12,99 €». Los que ignores en Gastos no avisan.")
        }
        .onChange(of: yago) { _, _ in Task { await AvisosRecurrentes.reprograma(.yago) } }
        .onChange(of: aitana) { _, _ in Task { await AvisosRecurrentes.reprograma(.aitana) } }
    }
}
