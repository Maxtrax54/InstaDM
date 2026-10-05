//
//  ContentView.swift
//  InstaDM
//
//  Pantalla principal: la web de Instagram respetando las safe areas, barra de
//  progreso, aviso tipo toast y barra inferior minimalista.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var modelo = NavegadorModelo()
    @State private var mostrarAjustes = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                InstagramWebView(modelo: modelo)

                // Barra de progreso fina mientras carga
                if modelo.cargando {
                    ProgressView(value: modelo.progreso)
                        .progressViewStyle(.linear)
                }

                // Indicador grande solo en la primera carga
                if !modelo.cargaInicialLista {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottom) { toast }

            barraInferior
        }
        // El teclado se superpone (como en Safari) en vez de empujar todo hacia arriba;
        // WebKit se encarga de dejar visible el campo de texto del chat.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $mostrarAjustes) {
            SettingsView(modelo: modelo)
        }
    }

    // MARK: Barra inferior

    private var barraInferior: some View {
        HStack(spacing: 0) {
            botonBarra("Volver", icono: "chevron.backward") { modelo.volver() }
                .disabled(!modelo.puedeVolver)
                .opacity(modelo.puedeVolver ? 1 : 0.3)

            botonBarra("Mensajes", icono: "paperplane",
                       activo: modelo.pathActual.hasPrefix("/direct")) {
                modelo.irAMensajes()
            }

            if modelo.modo == .mensajesEInicio {
                botonBarra("Inicio", icono: "house", activo: modelo.pathActual == "/") {
                    modelo.irAInicio()
                }
            }

            botonBarra("Ajustes", icono: "gearshape") { mostrarAjustes = true }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func botonBarra(_ titulo: String, icono: String, activo: Bool = false,
                            accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 3) {
                Image(systemName: activo ? "\(icono).fill" : icono)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(titulo)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(activo ? Color.primary : Color.secondary)
    }

    // MARK: Aviso (toast)

    private var toast: some View {
        ZStack {
            if let aviso = modelo.aviso {
                Text(aviso)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: modelo.aviso)
        .allowsHitTesting(false)
    }
}
