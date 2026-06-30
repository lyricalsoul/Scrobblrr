//
//  MessagesViewController.swift
//  Scrobblrr
//
//  Created by Renan Martins on 6/29/26.
//

import UIKit
import Messages
import SwiftUI

class MessagesViewController: MSMessagesAppViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView()
    }
    
    private func setupSwiftUIView() {
        // Instantiate your core SwiftUI view
        let extensionView = CollageComposeView { [weak self] generatedImage in
            self?.sendCollageMessage(image: generatedImage)
        }
        
        // Host the SwiftUI view inside a UIKit controller
        let hostingController = UIHostingController(rootView: extensionView)
        
        // Add the hosting controller as a child view controller
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        // Constraints to make it fill the keyboard container area
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
    
    private func sendCollageMessage(image: UIImage) {
        guard let conversation = activeConversation else { return }
        
        // 1. Create a template layout to display in the chat bubble
        let layout = MSMessageTemplateLayout()
        layout.image = image
        layout.caption = "Check out my new collage!"
        
        // 2. Wrap it inside an MSMessage block
        let message = MSMessage()
        message.layout = layout
        
        // (Optional) Add custom URL parameters if you want users to click and interact with it
        message.url = URL(string: "https://musicorumapp.com")
        
        // 3. Insert into the live chat input field
        conversation.insert(message) { error in
            if let error = error {
                print("Error inserting message: \(error.localizedDescription)")
            }
        }
    }
    
    // Trigger layout updates or model changes when a new message arrives
    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
    }
    
    // MARK: - Conversation Handling
    
    override func willBecomeActive(with conversation: MSConversation) {
        // Called when the extension is about to move from the inactive to active state.
        // This will happen when the extension is about to present UI.
        
        // Use this method to configure the extension and restore previously stored state.
    }
    
    override func didResignActive(with conversation: MSConversation) {
        // Called when the extension is about to move from the active to inactive state.
        // This will happen when the user dismisses the extension, changes to a different
        // conversation or quits Messages.
        
        // Use this method to release shared resources, save user data, invalidate timers,
        // and store enough state information to restore your extension to its current state
        // in case it is terminated later.
    }
    
    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        // Called when the user taps the send button.
    }
    
    override func didCancelSending(_ message: MSMessage, conversation: MSConversation) {
        // Called when the user deletes the message without sending it.
    
        // Use this to clean up state related to the deleted message.
    }
    
    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        // Called before the extension transitions to a new presentation style.
    
        // Use this method to prepare for the change in presentation style.
    }
    
    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        // Called after the extension transitions to a new presentation style.
    
        // Use this method to finalize any behaviors associated with the change in presentation style.
    }
}
