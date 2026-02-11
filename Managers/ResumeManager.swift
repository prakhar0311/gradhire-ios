//
//  ResumeManager.swift
//  GradHire
//
//  Created by Prakhar Ghirnikar on 09/02/26.
//


import Foundation
import Combine

final class ResumeManager: ObservableObject {
    @Published var resumeURL: URL? = nil
    @Published var resumeText: String?
}

