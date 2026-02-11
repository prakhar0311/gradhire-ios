//
//  ShareSheet.swift
//  GradHire
//
//  Created by Prakhar Ghirnikar on 09/02/26.
//
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {

let items: [Any]

func makeUIViewController(context: Context)
    -> UIActivityViewController {

    UIActivityViewController(
        activityItems: items,
        applicationActivities: nil
    )
}

func updateUIViewController(
    _ vc: UIActivityViewController,
    context: Context
) {}


}
