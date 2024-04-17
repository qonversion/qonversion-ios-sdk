//
//  ViewController.swift
//  Sample
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import UIKit
import Qonversion

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Qonversion.Configuration.init(apiKey: <#T##String#>, launchMode: <#T##LaunchMode#>)
        Qonversion.shared.collectAdvertisingId()
        // Do any additional setup after loading the view.
    }

}

