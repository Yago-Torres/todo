import SwiftUI

/// La rutina guiada a pantalla completa: el paso, su monigote, la cuenta atrás grande, la barra, cómo hacerlo y lo
/// que viene. Pausa y Saltar abajo, grandes.
struct VistaGuia: View {
    @State private var guia = GuiaEnCurso.shared

    var body: some View {
        ZStack {
            Tema.fondo.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(guia.rutina?.n ?? "Rutina").font(Tema.fuente(.destacado)).foregroundStyle(Tema.texto).lineLimit(1)
                    Spacer()
                    Button("Salir") { guia.para() }
                        .font(Tema.fuente(.texto, peso: .medium))
                        .foregroundStyle(Tema.texto)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Tema.carta2, in: Capsule())
                }
                .padding(.horizontal, Tema.Espacio.l)
                .padding(.vertical, Tema.Espacio.m)
                .background(Tema.carta)
                centro
                HStack(spacing: Tema.Espacio.m) {
                    Button(guia.pausa ? "Seguir" : "Pausa") { guia.alternaPausa() }
                        .buttonStyle(BotonEnt(alto: 60))
                    Button("Saltar") { guia.salta() }
                        .buttonStyle(BotonEnt(principal: true, alto: 60))
                }
                .padding(Tema.Espacio.l)
                .background(Tema.carta.ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private var centro: some View {
        VStack(spacing: Tema.Espacio.l) {
            Spacer(minLength: 0)
            if let r = guia.rutina, let b = guia.paso {
                Text("\(guia.cambio ? "Prepárate · " : "")Paso \(guia.indiceVisible + 1) de \(r.bloques.count)")
                    .font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                if let m = MonigoteDatos.de(b.ej) {
                    Monigote(datos: m).frame(maxWidth: 260)
                }
                Text(b.ej)
                    .font(Tema.fuente(.titulo)).foregroundStyle(Tema.texto)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text("\(guia.queda)")
                    .font(.system(size: 96, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Tema.acento)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: guia.queda)
                    .accessibilityLabel("Quedan \(guia.queda) segundos")
                BarraEnt(valor: 1 - Double(guia.queda) / Double(guia.totalPaso))
                    .frame(height: 8)
                    .animation(.linear(duration: 0.25), value: guia.queda)
                if !b.nota.isEmpty {
                    Text(b.nota).font(Tema.fuente(.texto)).foregroundStyle(Tema.suave)
                        .multilineTextAlignment(.center).frame(maxWidth: 340)
                }
                Text(guia.siguiente.map { "Luego: \($0.ej)" } ?? "Último")
                    .font(Tema.fuente(.pequeno)).foregroundStyle(Tema.tenue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tema.Espacio.xl)
        .animation(Tema.Muelle.pantalla, value: guia.indiceVisible)
    }
}
