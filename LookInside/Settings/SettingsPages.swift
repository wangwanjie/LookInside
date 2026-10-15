//
//  SettingsPages.swift
//  LookInside
//
//  Native SwiftUI settings navigation, kept in the host so the app can build
//  with the Swift 6.1 toolchain shipped by Xcode 16.4.

import SwiftUI

struct SettingsPages: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general
        case privateDiscriminator

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                String(localized: "General", comment: "Title of the Settings window's General page.")
            case .privateDiscriminator:
                String(localized: "Private Discriminator", comment: "Title of the Settings window's Private Discriminator page.")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privateDiscriminator: "number"
            }
        }
    }

    @State private var selection: Page? = .general
    @State private var generalModel = GeneralSettingsModel()

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsPage(model: generalModel)
                case .privateDiscriminator:
                    PrivateDiscriminatorSettingsPage()
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 735, minHeight: 520)
    }
}
