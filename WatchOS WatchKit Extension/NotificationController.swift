//
//  NotificationController.swift
//  WatchOS WatchKit Extension
//
//  Created by Surik Sarkisyan on 15.06.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

import WatchKit
import Foundation
import UserNotifications

class NotificationController: WKUserNotificationInterfaceController {

    override init() {
        // Initialize variables here.
        super.init()
        
        // Configure interface objects here.
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
    }

    override func didReceive(_ notification: UNNotification) {
        // This method is called when a notification needs to be presented.
        // Implement it if you use a dynamic notification interface.
        // Populate your dynamic notification interface as quickly as possible.
    }
}
