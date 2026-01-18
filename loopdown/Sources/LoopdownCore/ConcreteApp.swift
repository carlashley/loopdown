//// ConcreteApp.swift
// loopdown
//
// Created on 18/1/2026
//
    

// MARK: ConcreteApp
public enum ConcreteApp: String, CaseIterable {
    case garageband
    case logicpro
    case logicprox
    case mainstage

    public var displayName: String {
        switch self {
        case .garageband: return "GarageBand"
        case .logicpro:   return "Logic Pro"
        case .logicprox:  return "Logic Pro X"
        case .mainstage:  return "MainStage"
        }
    }
}
