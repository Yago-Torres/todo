import SwiftUI
import WidgetKit

enum EstadoWidget {
    case sinClaves
    case datos(Hoy)
    case sinDatos(String)
}

struct Entrada: TimelineEntry {
    let date: Date
    let estado: EstadoWidget
}

struct Proveedor: TimelineProvider {
    func placeholder(in context: Context) -> Entrada {
        Entrada(date: Date(), estado: .datos(Hoy.muestra))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        if context.isPreview {
            completion(Entrada(date: Date(), estado: .datos(Hoy.muestra)))
            return
        }
        Task { completion(Entrada(date: Date(), estado: await Proveedor.carga())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        Task {
            let ahora = Date()
            let estado = await Proveedor.carga()
            var entradas = [Entrada(date: ahora, estado: estado)]
            // a las 20 h aparece el aviso de «racha en juego» aunque iOS no refresque antes
            if let veinte = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: ahora), veinte > ahora {
                entradas.append(Entrada(date: veinte, estado: estado))
            }
            let siguiente = ahora.addingTimeInterval(15 * 60)
            completion(Timeline(entries: entradas, policy: .after(siguiente)))
        }
    }

    /// También la usa el widget configurable (DatoWidget.swift): misma red y misma caché.
    static func carga() async -> EstadoWidget {
        guard Almacen.claves != nil else { return .sinClaves }
        do {
            return .datos(try await API.hoy())
        } catch {
            if let guardado = Almacen.leeHoy() { return .datos(guardado) }
            return .sinDatos(error.localizedDescription)
        }
    }
}

extension Hoy {
    static var muestra: Hoy {
        Hoy(hoy: Fecha.hoy(),
            habitos: [
                Habito(id: "a", n: "Entreno", c: "#1baf7a", plan: true, hecho: true, racha: 4),
                Habito(id: "b", n: "Leer", c: "#3987e5", plan: true, hecho: false, racha: 2),
                Habito(id: "c", n: "Core", c: "#eb6834", plan: false, hecho: false, racha: 0),
            ],
            salud: SaludHoy(sueno: DatoSalud(ultimo: 420, media: 430, serie: nil),
                            pasos: DatoSalud(ultimo: 7500, media: 8000, serie: nil)),
            tareas: [Tarea(t: "Llamar al dentista", due: nil, hora: "10:30", id: nil)],
            carrera: nil,
            ayer: nil)
    }
}

/// El widget principal. El tipo no se llama como el módulo (HoyWidget) para que no lo tape; el `kind` sigue siendo
/// "HoyWidget", así que los widgets ya puestos no se pierden.
struct WidgetHoy: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyWidget", provider: Proveedor()) { entrada in
            HoyWidgetVista(entrada: entrada)
        }
        .configurationDisplayName("Tom")
        .description("Anillos de hábitos, pasos y sueño con su leyenda; marca hábitos y completa tareas desde el widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Todo lo que sale en la galería, en grupos de menos de diez (el límite de WidgetBundleBuilder en un mismo bloque
/// en iOS 17): los widgets de pantalla, las Live Activities y, desde iOS 18, los controles.
@main
struct HoyWidgets: WidgetBundle {
    var body: some Widget {
        WidgetsDePantalla().body
        WidgetsVivos().body
        if #available(iOS 18.0, *) {
            ControlesTom().body
        }
    }
}

struct WidgetsDePantalla: WidgetBundle {
    var body: some Widget {
        WidgetHoy()
        HoyDatoWidget()
        PendientesWidget()
        EntrenoWidget()
        PresupuestoWidget()
        SuenoWidget()
        RachaWidget()
        SemanaWidget()
        MomentoWidget()
    }
}

struct WidgetsVivos: WidgetBundle {
    var body: some Widget {
        EntrenoLiveActivity()
        AvisoLiveActivity()
    }
}

@available(iOS 18.0, *)
struct ControlesTom: WidgetBundle {
    var body: some Widget {
        HablaConTomControl()
        ApuntaTareaControl()
        MarcaHabitoControl()
        AbreSeccionControl()
    }
}
