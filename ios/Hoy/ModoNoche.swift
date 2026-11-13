import SwiftUI
import UIKit

/// Un fundido de toda la pantalla: foto de cómo está, el cambio debajo y la foto que se desvanece. Sirve para lo que
/// SwiftUI no anima solo, como pasar de claro a oscuro al entrar el modo noche.
@MainActor
enum TransicionFundido {
    static func cambia(duracion: Double = 1.1, _ cambio: @escaping () -> Void) {
        guard UIApplication.shared.applicationState == .active,
              let ventana = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              let foto = ventana.snapshotView(afterScreenUpdates: false) else {
            cambio()
            return
        }
        foto.frame = ventana.bounds
        foto.isUserInteractionEnabled = false
        ventana.addSubview(foto)
        cambio()
        UIView.animate(withDuration: duracion, delay: 0.05, options: [.curveEaseInOut, .allowUserInteraction]) {
            foto.alpha = 0
        } completion: { _ in
            foto.removeFromSuperview()
        }
    }
}

/// Configurar → Apariencia → Modo noche: el interruptor, por horas o con el sol, y las horas.
struct SeccionNoche: View {
    @State private var ajustes = Noche.ajustes

    var body: some View {
        let aspecto = Aspecto.shared
        Section {
            Toggle("Modo noche", isOn: $ajustes.activo)
            if ajustes.activo {
                Picker("Cuándo", selection: $ajustes.modo) {
                    Text("Por horas").tag(AjustesNoche.Modo.horas)
                    Text("Con el sol").tag(AjustesNoche.Modo.sol)
                }
                if ajustes.modo == .horas {
                    DatePicker("Desde", selection: hora(\.desde), displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: hora(\.hasta), displayedComponents: .hourAndMinute)
                } else {
                    let t = Noche.tramo(Date(), ajustes)
                    LabeledContent("Hoy", value: "de \(Noche.hora(t.desde)) a \(Noche.hora(t.hasta))")
                }
                LabeledContent("Ahora", value: aspecto.noche ? "Activo" : "Apagado")
                    .contentTransition(.opacity)
            }
        } header: {
            Text("Modo noche")
        } footer: {
            Text(ajustes.modo == .sol && ajustes.activo
                 ? "De la puesta a la salida del sol (calculadas sin pedir tu ubicación: con la hora de Madrid, o de Canarias si tu iPhone está en esa hora). Tom se pone en oscuro, con colores más cálidos y menos brillo; los widgets también."
                 : "Tom se pone en oscuro, con colores más cálidos y menos brillo, para no deslumbrarte de noche. Los widgets también. Fuera de esas horas vuelve tu tema.")
        }
        .onChange(of: ajustes) { _, nuevo in
            Haptica.shared.toca(.marcar)
            aspecto.ponNoche(nuevo)
        }
        .animation(Tema.Muelle.toque, value: ajustes)
    }

    /// Los minutos desde medianoche como la fecha de hoy a esa hora (lo que pide el DatePicker).
    private func hora(_ campo: WritableKeyPath<AjustesNoche, Int>) -> Binding<Date> {
        Binding(get: {
            let m = ajustes[keyPath: campo]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { fecha in
            let c = Calendar.current.dateComponents([.hour, .minute], from: fecha)
            ajustes[keyPath: campo] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
}
