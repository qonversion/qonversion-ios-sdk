//
//  InterfaceController.swift
//  WatchOS WatchKit Extension
//
//  Created by Surik Sarkisyan on 15.06.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

import WatchKit
import Foundation
//import Qonversion

class InterfaceController: WKInterfaceController {

    override func awake(withContext context: Any?) {
        // Configure interface objects here.
      print("lala")
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
    }

}
