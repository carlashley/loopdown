//// CacheServer+ArgumentParser.swift
// loopdown
//
// Created on 27/3/2026
//
    

import ArgumentParser
import Foundation
import LoopdownInfrastructure


// MARK: - CacheServer + ExpressibleByArgument

extension CacheServer: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        if argument.lowercased() == "auto" {
            self = .auto
            return
        }
        guard let url = URL(string: argument), url.scheme != nil else { return nil }
        self = .url(url)
    }
}


// MARK: - MirrorServer + ExpressibleByArgument

extension MirrorServer: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(urlString: argument)
    }
}
