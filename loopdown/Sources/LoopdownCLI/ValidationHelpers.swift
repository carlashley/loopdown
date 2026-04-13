//// ValidationHelpers.swift
// loopdown
//
// Created on 18/1/2026
//

import ArgumentParser


// MARK: - Validation helpers

/// Ensure at least one of `-e/--esn`, `-c/--core`, or `-o/--optional` is provided.
public func validateContentSelection(essential: Bool, core: Bool, optional: Bool) throws {
    guard essential || core || optional else {
        throw ValidationError(
            "You must specify at least one of '-e/--essential', '-c/--core', or '-o/--optional'."
        )
    }
}
