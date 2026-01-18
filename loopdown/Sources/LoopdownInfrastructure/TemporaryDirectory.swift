//// TemporaryDirectory.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation


// MARK: - Temporary directory
public final class TemporaryDirectory {
    public let url: URL
    private var shouldDelete = true

    public init(prefix: String = "loopdown-staging-", fileManager: FileManager = .default) throws {
        let base = fileManager.temporaryDirectory
        let dir = base.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        self.url = dir
    }

    func keep() { shouldDelete = false }

    public func cleanup(fileManager: FileManager = .default) {
        guard shouldDelete else { return }
        try? fileManager.removeItem(at: url)
        shouldDelete = false
    }

    deinit { cleanup() }
}

