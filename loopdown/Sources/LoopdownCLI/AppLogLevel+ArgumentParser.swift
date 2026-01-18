//// AppLogLevel+ArgumentParser.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation
import ArgumentParser
import LoopdownInfrastructure


// MARK: - AppLogLevel extension for command line arguments
extension AppLogLevel: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(parsing: argument)
    }

    public static var defaultCompletionKind: CompletionKind {
        .list(Self.allCases.map(\.rawValue))
    }
}
