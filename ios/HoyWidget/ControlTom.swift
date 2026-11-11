import AppIntents
import SwiftUI
import WidgetKit

/// «Habla con Tom» en el centro de control (y en el botón de acción o la pantalla de bloqueo): abre el modo voz.
@available(iOS 18.0, *)
struct HablaConTomControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.yagotg.hoy.voz") {
            ControlWidgetButton(action: HablaConTomIntent()) {
                Label("Habla con Tom", systemImage: "waveform")
            }
        }
        .displayName("Habla con Tom")
        .description("Abre Tom en modo voz.")
    }
}
