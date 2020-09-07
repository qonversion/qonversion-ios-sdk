//
//  ViewController.swift
//  Sample
//
//  Created by Sam Mejlumyan on 13.08.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion

class ViewController: UIViewController {

  override func viewDidLoad() {
    super.viewDidLoad()
  
    let deadlineTime = DispatchTime.now() + .seconds(3)
    DispatchQueue.main.asyncAfter(deadline: deadlineTime) {
      Qonversion.restore { (result, error, flag) in
        print(result)
      }
    }
  }

}
