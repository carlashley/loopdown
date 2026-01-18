//// PrivilegeCheck.swift
// loopdown
//
// Created on 18/1/2026
//
    

import Foundation

#if canImport(Darwin)
import Darwin
#endif


// MARK: - Privilege Check (must be root to install)
public enum PrivilegeCheck {
    public static var isRoot: Bool {
        geteuid() == 0
    }
}
