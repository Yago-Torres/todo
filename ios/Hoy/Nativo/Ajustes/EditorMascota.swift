import SwiftUI

/// Ajustes → Tu mascota: tipo (fantasma o flor), color, forma con deslizadores, extra, rubor y paseo. Es el mismo objeto
/// «mascota» que edita la web, así que lo que cambies aquí se ve allí y al revés.
struct EditorMascota: View {
    @State private var modelo = ModeloAjustes.shared

    var body: some View {
        List {
            if let m = modelo.ajustes?.mascota {
                Section {
                    // ↓ AQUÍ va la mascota nativa de verdad (Hoy/Nativo/Mascota/) cuando exista; mientras, un dibujo sencillo
                    // que ya responde a los deslizadores y al color.
                    HuecoVistaMascota(mascota: m)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Tema.carta2)
                    Picker("Es", selection: Binding(get: { m.tipo }, set: { v in
                        Haptica.shared.toca(.marcar)
                        cambia { $0.tipo = v }
                    })) {
                        Text("Un fantasma").tag("fantasma")
                        Text("Una flor de boli").tag("flor")
                    }
                    .pickerStyle(.segmented)
                    Button {
                        Haptica.shared.toca(.marcar)
                        cambia { $0.semilla = Int.random(in: 1...9999) }
                    } label: {
                        Label("Otra forma", systemImage: "dice")
                    }
                }

                if m.tipo == "fantasma" {
                    Section("Forma") {
                        ForEach(MascotaAjustes.controles) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(c.nombre).font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
                                    Spacer()
                                    Text(valor(m[keyPath: c.valor], paso: c.paso)).font(Tema.fuente(.pequeno)).monospacedDigit()
                                        .foregroundStyle(Tema.texto)
                                }
                                Slider(value: Binding(get: { m[keyPath: c.valor] }, set: { v in
                                    cambia { $0[keyPath: c.valor] = (v / c.paso).rounded() * c.paso }
                                }), in: c.rango)
                                .accessibilityLabel(c.nombre)
                            }
                        }
                    }
                    Section("Detalles") {
                        ColorPicker("Color", selection: Binding(get: { Color(hex: m.color) }, set: { v in
                            cambia { $0.color = hexDe(v) }
                        }), supportsOpacity: false)
                        Picker("Lleva", selection: Binding(get: { m.extra }, set: { v in cambia { $0.extra = v } })) {
                            Text("Nada").tag("")
                            Text("Lazo").tag("lazo")
                            Text("Gorro").tag("gorro")
                            Text("Gafas").tag("gafas")
                        }
                        Toggle("Rubor", isOn: Binding(get: { m.rubor }, set: { v in cambia { $0.rubor = v } }))
                    }
                }

                Section {
                    Toggle("Pasea por la web", isOn: Binding(get: { m.paseo }, set: { v in cambia { $0.paseo = v } }))
                } footer: {
                    Text("Los cambios se guardan solos. La flor es un dibujo: de ella solo eliges el garabato con «Otra forma».")
                }
            } else {
                Text("Tus ajustes aún no han llegado. Vuelve a abrir esta pantalla con conexión.")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.suave)
            }
        }
        .listRowBackground(Tema.carta)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        .task { await modelo.carga() }
    }

    private func cambia(_ f: @escaping (inout MascotaAjustes) -> Void) {
        modelo.cambia { f(&$0.mascota) }
    }

    private func valor(_ v: Double, paso: Double) -> String {
        paso >= 1 ? String(Int(v.rounded())) : String(format: paso < 0.1 ? "%.2f" : "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// "#RRGGBB" de un Color (lo que devuelve el ColorPicker).
private func hexDe(_ c: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
    func canal(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", canal(r), canal(g), canal(b))
}

/// EL HUECO de la vista previa de la mascota. Cuando exista la mascota nativa (Hoy/Nativo/Mascota/), se sustituye el
/// cuerpo de esta vista por ella, pasándole `mascota` (los mismos campos que la web). Mientras tanto, un dibujo
/// simple: cuerpo del color elegido con el ancho, el alto y la pera, y los ojos donde dicen los deslizadores.
struct HuecoVistaMascota: View {
    let mascota: MascotaAjustes

    var body: some View {
        MascotaVista(ajustes: mascota)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    /// El dibujo provisional de antes (ya no se usa).
    private var provisional: some View {
        ZStack {
            if mascota.tipo == "flor" {
                Image(systemName: "camera.macro")
                    .font(.system(size: 84))
                    .foregroundStyle(Color(hex: mascota.color))
            } else {
                fantasma
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .animation(Tema.Muelle.toque, value: mascota)
        .accessibilityLabel(mascota.tipo == "flor" ? "Vista previa: una flor" : "Vista previa: un fantasma")
    }

    private var fantasma: some View {
        // las medidas de la web están en unidades de un dibujo de ~100 de alto: aquí se escalan a la caja
        let k: CGFloat = 1.8
        let ancho = CGFloat(mascota.ancho) * k * 1.6
        let alto = CGFloat(mascota.alto) * k
        let pera = CGFloat(mascota.pera)
        return ZStack {
            UnevenRoundedRectangle(topLeadingRadius: ancho / 2, bottomLeadingRadius: 10 + 20 * pera,
                                   bottomTrailingRadius: 10 + 20 * pera, topTrailingRadius: ancho / 2, style: .continuous)
                .fill(Color(hex: mascota.color))
                .frame(width: ancho * (1 - 0.1 * pera), height: alto)
            let y = -alto / 2 + alto * CGFloat(mascota.ojosY) + 8
            let s = CGFloat(mascota.sep) * k / 2
            Circle().fill(Color.black.opacity(0.8)).frame(width: CGFloat(mascota.ojoI) * k * 1.4)
                .offset(x: -s, y: y)
            Circle().fill(Color.black.opacity(0.8)).frame(width: CGFloat(mascota.ojoD) * k * 1.4)
                .offset(x: s, y: y)
            if mascota.rubor {
                Circle().fill(Color.red.opacity(0.25)).frame(width: 14).offset(x: -s - 12, y: y + 14)
                Circle().fill(Color.red.opacity(0.25)).frame(width: 14).offset(x: s + 12, y: y + 14)
            }
        }
        .frame(maxHeight: 180)
    }
}
