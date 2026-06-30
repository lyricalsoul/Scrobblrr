//
//  CollageComposeView.swift
//  Scrobblr
//
//  Created by Renan Martins on 6/29/26.
//

import SwiftUI
import SwiftData

struct CollageComposeView: View {
    @State private var collageImage: UIImage?
    @State private var isLoading = false
    
    // Callback to pass the image back to MSMessagesAppViewController
    var onSendCollage: (UIImage) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
                Text("Generating collage for me!")
                    .font(.headline)
                
                if isLoading {
                    ProgressView()
                } else if let collageImage = collageImage {
                    Image(uiImage: collageImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                    
                    Button("Send Collage") {
                        onSendCollage(collageImage)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Generate Collage") {
                        fetchCollage(for: "BlueSlimee")
                    }
                    .buttonStyle(.bordered)
                }
            //} else {
            //    Text("Please configure your username in the main app first.")
            //        .foregroundColor(.red)
            //s}
        }
        .padding()
    }
    
    // Simple mock API call
    func fetchCollage(for username: String) {
        isLoading = true
        guard let url = URL(string: "https://example.com\(username)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.collageImage = image
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }
}

