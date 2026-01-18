//// ConcreteApp+ArgumentParser.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownCore

extension ConcreteApp: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "garageband": self = .garageband
        case "logicpro": self = .logicpro
        case "mainstage": self = .mainstage
        default: return nil
        }
    }
}
