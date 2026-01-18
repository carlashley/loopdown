//// ServerArguments.swift
// loopdown
//
// Created on 18/1/2026
//
    

import ArgumentParser
import Foundation


// MARK: - CacheServer arguments
enum CacheServer: ExpressibleByArgument, CustomStringConvertible, Equatable {
    case auto
    case url(URL)

    init?(argument: String) {
        if argument.lowercased() == "auto" {
            self = .auto
            return
        }
        guard let url = URL(string: argument), url.scheme != nil else { return nil }
        self = .url(url)
    }

    var description: String {
        switch self {
        case .auto: return "auto"
        case .url(let url): return url.absoluteString
        }
    }
}


// MARK: Mirroring Server arguments
enum MirrorServer: ExpressibleByArgument, CustomStringConvertible, Equatable {
    case url(URL)

    init?(argument: String) {
        guard let url = URL(string: argument), url.scheme != nil else { return nil }
        self = .url(url)
    }

    var description: String {
        switch self {
        case .url(let url): return url.absoluteString
        }
    }
}
