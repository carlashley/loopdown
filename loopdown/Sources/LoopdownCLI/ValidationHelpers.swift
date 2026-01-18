//// ValidationHelpers.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser


// MARK: - Validation helpers

/// Ensure at least `-r/--required` and/or `-o/--optional` are provided in `deploy` and `download` commands.
public func validateContentSelection(required: Bool, optional: Bool) throws {
    guard required || optional else {
        throw ValidationError("You must specifiy at least one of '-r/--required' or '-o/--optional'.")
    }
}
