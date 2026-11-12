import Foundation
import HealthKit

/// Lee Salud y se lo manda al servidor (/api/salud y /api/entreno). Sustituye al atajo de iOS de cada mañana.
enum Salud {
    private static let almacen = HKHealthStore()
    private static let cerrojo = NSLock()
    private static var enCurso = false
    private static var observadores: [HKObserverQuery] = []
    private static let claveEnviados = "saludEntrenosEnviados"

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var tiposLectura: Set<HKObjectType> {
        var tipos: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { tipos.insert(t) }
        let cantidades: [HKQuantityTypeIdentifier] = [.stepCount, .bodyMass, .distanceWalkingRunning]
        for id in cantidades {
            if let t = HKObjectType.quantityType(forIdentifier: id) { tipos.insert(t) }
        }
        return tipos
    }

    /// nil si va bien; si no, por qué (sin el permiso de HealthKit en la firma, iOS ni enseña la hoja de Salud).
    static func autoriza() async -> String? {
        guard disponible else { return "Este dispositivo no tiene Salud." }
        guard firmadaConSalud else {
            return "La firma de Tom no lleva el permiso de Salud (com.apple.developer.healthkit): SideStore lo ha quitado al instalar. Sin él, iOS no deja ni pedir acceso."
        }
        do {
            try await almacen.requestAuthorization(toShare: [], read: tiposLectura)
            return nil
        } catch {
            return "Salud: \(error.localizedDescription)"
        }
    }

    /// Sin perfil embebido (simulador) se da por bueno.
    static var firmadaConSalud: Bool {
        let d = Firma.derechos()
        return d.isEmpty || (d["com.apple.developer.healthkit"] as? Bool ?? false)
    }

    /// Manda sueño, pasos, peso y entrenos. Devuelve el texto que contesta el servidor, o nil si no hubo nada o falló.
    @discardableResult
    static func sincroniza() async -> String? {
        guard Almacen.defaults.bool(forKey: "salud"), disponible else { return nil }
        // el observador y el primer plano pueden disparar a la vez: una sola pasada
        cerrojo.lock()
        if enCurso { cerrojo.unlock(); return nil }
        enCurso = true
        cerrojo.unlock()
        defer { cerrojo.lock(); enCurso = false; cerrojo.unlock() }

        var resumen: [String] = []
        if let t = await sincronizaSalud() { resumen.append(t) }
        resumen += await sincronizaEntrenos()
        return resumen.isEmpty ? nil : resumen.joined(separator: "\n")
    }

    // MARK: sueño, pasos y peso

    private static func sincronizaSalud() async -> String? {
        var json: [String: Any] = [:]
        if let l = try? await lineasSueno(), !l.isEmpty { json["fases"] = l.joined(separator: "\n") }
        if let l = try? await lineasPasos(), !l.isEmpty { json["pasos"] = l.joined(separator: "\n") }
        if let l = try? await lineasPeso(), !l.isEmpty { json["peso"] = l.joined(separator: "\n") }
        guard !json.isEmpty else { return nil }
        return await manda("/api/salud", json)
    }

    private static func etapa(_ valor: Int) -> (nombre: String, conFases: Bool)? {
        switch HKCategoryValueSleepAnalysis(rawValue: valor) {
        case .asleepDeep: return ("Deep", true)
        case .asleepREM: return ("REM", true)
        case .asleepCore: return ("Core", true)
        case .asleepUnspecified: return ("Core", false)
        case .awake: return ("Awake", false)
        default: return nil   // inBed no es una fase
        }
    }

    private static func lineasSueno() async throws -> [String] {
        guard let tipo = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let desde = Date().addingTimeInterval(-48 * 3600)
        let pred = HKQuery.predicateForSamples(withStart: desde, end: nil, options: [])
        let consulta = HKSampleQueryDescriptor(predicates: [.categorySample(type: tipo, predicate: pred)],
                                               sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)])
        let muestras = try await consulta.result(for: almacen)

        struct Tramo { var etapa: String; var inicio: Date; var seg: Int }
        var porFuente: [String: (tramos: [Tramo], conFases: Int, dormido: Int)] = [:]
        for m in muestras {
            guard let e = etapa(m.value) else { continue }
            let seg = Int(m.endDate.timeIntervalSince(m.startDate))
            guard seg > 0 else { continue }
            let clave = m.sourceRevision.source.bundleIdentifier
            var f = porFuente[clave] ?? (tramos: [], conFases: 0, dormido: 0)
            f.tramos.append(Tramo(etapa: e.nombre, inicio: m.startDate, seg: seg))
            if e.nombre != "Awake" {
                f.dormido += seg
                if e.conFases { f.conFases += seg }
            }
            porFuente[clave] = f
        }
        // el servidor rechaza más de 16 h: iPhone y reloj se sumarían. Una sola fuente: la que tiene fases, o la que más duerme
        guard let mejor = porFuente.values.max(by: { ($0.conFases, $0.dormido) < ($1.conFases, $1.dormido) }) else { return [] }
        let lineas = mejor.tramos.map { "\($0.etapa)|\(Fecha.minuto($0.inicio))|\($0.seg)" }
        return Array(lineas.suffix(400))   // el servidor lee 400 líneas como mucho
    }

    private static func lineasPasos() async throws -> [String] {
        guard let tipo = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        let hoy0 = cal.startOfDay(for: Date())
        guard let desde = cal.date(byAdding: .day, value: -6, to: hoy0) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: desde, end: nil, options: .strictStartDate)
        let coleccion: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: tipo, quantitySamplePredicate: pred,
                                                options: .cumulativeSum, anchorDate: hoy0,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, resultado, error in
                if let resultado {
                    cont.resume(returning: resultado)
                } else {
                    cont.resume(throwing: error ?? APIError(mensaje: "Salud no devolvió pasos"))
                }
            }
            almacen.execute(q)
        }
        var lineas: [String] = []
        coleccion.enumerateStatistics(from: desde, to: Date()) { s, _ in
            let n = Int((s.sumQuantity()?.doubleValue(for: .count()) ?? 0).rounded())
            if n > 0 { lineas.append("\(Fecha.dia(s.startDate)) 00:00|\(n)") }
        }
        return lineas
    }

    private static func lineasPeso() async throws -> [String] {
        guard let tipo = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let desde = Date().addingTimeInterval(-7 * 24 * 3600)
        let pred = HKQuery.predicateForSamples(withStart: desde, end: nil, options: .strictStartDate)
        let consulta = HKSampleQueryDescriptor(predicates: [.quantitySample(type: tipo, predicate: pred)],
                                               sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)])
        let muestras = try await consulta.result(for: almacen)
        return muestras.map { m in
            let kg = m.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            return "\(Fecha.minuto(m.startDate))|\(String(format: "%.1f", kg))"
        }
    }

    // MARK: entrenos

    private static func tipoServidor(_ t: HKWorkoutActivityType) -> String? {
        switch t {
        case .running: return "running"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        case .climbing: return "climbing"
        default: return nil
        }
    }

    private static func sincronizaEntrenos() async -> [String] {
        let desde = Date().addingTimeInterval(-3 * 24 * 3600)
        let pred = HKQuery.predicateForSamples(withStart: desde, end: nil, options: .strictStartDate)
        let consulta = HKSampleQueryDescriptor(predicates: [.sample(type: HKObjectType.workoutType(), predicate: pred)],
                                               sortDescriptors: [SortDescriptor(\HKSample.startDate)])
        guard let muestras = try? await consulta.result(for: almacen) else { return [] }
        var enviados = Almacen.defaults.stringArray(forKey: claveEnviados) ?? []
        var textos: [String] = []
        for muestra in muestras {
            guard let w = muestra as? HKWorkout, let tipo = tipoServidor(w.workoutActivityType),
                  !enviados.contains(w.uuid.uuidString) else { continue }
            let metros = w.totalDistance?.doubleValue(for: .meter()) ?? 0
            let json: [String: Any] = [
                "tipo": tipo,
                "km": (metros / 10).rounded() / 100,
                "seg": Int(w.duration),
                "dia": Fecha.dia(w.startDate),
                "id": Fecha.minuto(w.startDate),   // 16 caracteres: el servidor corta en 20 y con él deduplica iPhone y reloj
                "src": "salud",
            ]
            if let t = await manda("/api/entreno", json) {
                textos.append(t)
                enviados.append(w.uuid.uuidString)
            }
        }
        Almacen.defaults.set(Array(enviados.suffix(100)), forKey: claveEnviados)
        return textos
    }

    private static func manda(_ ruta: String, _ json: [String: Any]) async -> String? {
        do {
            let datos = try await API.datos(ruta, metodo: "POST", json: json)
            let objeto = try? JSONSerialization.jsonObject(with: datos)
            let texto = (objeto as? [String: Any])?["texto"] as? String
            return texto ?? "Apuntado"
        } catch {
            return nil
        }
    }

    // MARK: segundo plano

    /// Salud despierta a la app cuando hay datos nuevos (sueño al apagar la alarma, entrenos al acabar, peso al pesarte).
    static func activaSegundoPlano() {
        guard disponible, Almacen.defaults.bool(forKey: "salud"), observadores.isEmpty else { return }
        var tipos: [(HKObjectType, HKUpdateFrequency)] = [(HKObjectType.workoutType(), .immediate)]
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { tipos.append((t, .hourly)) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) { tipos.append((t, .hourly)) }
        for (tipo, frecuencia) in tipos {
            guard let muestra = tipo as? HKSampleType else { continue }
            let q = HKObserverQuery(sampleType: muestra, predicate: nil) { _, terminado, error in
                guard error == nil else { terminado(); return }
                Task {
                    await sincroniza()
                    terminado()
                }
            }
            almacen.execute(q)
            observadores.append(q)
            almacen.enableBackgroundDelivery(for: muestra, frequency: frecuencia) { _, _ in }
        }
    }
}
