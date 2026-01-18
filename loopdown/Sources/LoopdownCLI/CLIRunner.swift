//// CLIRunner.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import LoopdownInfrastructure


// MARK: - Command Line Runner
enum CLIRunner {
    static func runLocked(_ body: () throws -> Void) throws {
        do {
            try ExecutionLock.withLock(body)
        } catch let e as ExecutionLock.LockError {
            throw ValidationError(e.description)
        }
    }
}
