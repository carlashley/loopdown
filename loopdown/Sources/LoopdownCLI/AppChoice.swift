//// AppChoice.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownCore


// MARK: - App choice
enum AppChoice: ExpressibleByArgument {
    case auto
    case app(ConcreteApp)

    init?(argument: String) {
        let s = argument.lowercased()

        if s == "auto" {
            self = .auto
            return
        }

        switch s {
        case "gb", "garageband":
            self = .app(.garageband)
        case "lp", "logic", "logicpro":
            self = .app(.logicpro)
        case "lpx", "logicx", "logicprox":
            self = .app(.logicprox)
        case "ms", "mainstage":
            self = .app(.mainstage)
        default:
            return nil
        }
    }

    var expandedApps: [ConcreteApp] {
        switch self {
        case .auto:
            return ConcreteApp.allCases
        case .app(let app):
            return [app]
        }
    }
}
