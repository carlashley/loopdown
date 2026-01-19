//// Collection+Enumerated.swift
// loopdown
//
// Created on 19/1/2026
//
    

// MARK: - Collection extension
public extension Collection {
    /// Enumerate elements starting at an arbitrary index
    ///
    /// Example:
    /// ```
    /// for (i, value) in values.enumerated() { ... }              // starts at 0
    /// ```
    /// ```
    /// for (i, value) in values.enumerated(startingAt: 1) { ... } // starts at 1
    /// ```
    func enumerated(startingAt start: Int = 0) -> some Sequence<(Int, Element)> {
        zip(start..., self)
    }
}
