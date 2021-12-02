//
//  AuthViewController.swift
//  Sample
//
//  Created by Maria on 02.12.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

import UIKit
import GoogleSignIn
import FirebaseAuth

class AuthViewController: UIViewController {

  @IBOutlet var signInButton: GIDSignInButton!
  
    override func viewDidLoad() {
        super.viewDidLoad()
      
      guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
      
      GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, err in
        self?.showMainScreen()
      }
    }
    
  @IBAction func didTouchSignInButton(_ sender: Any) {
    let conf = GIDConfiguration(clientID: "11599271839-qalspkpqrihnkl1e12be731tgmre5uop.apps.googleusercontent.com")
    GIDSignIn.sharedInstance.signIn(with: conf, presenting: self) { [weak self] user, error in
      guard let error = error else {
        self?.showMainScreen()
        return
      }
      
      print(error)
      // handle error here
    }
  }
  
  func showMainScreen() {
    let viewController = self.storyboard?.instantiateViewController(withIdentifier: "MainViewController") as! ViewController
    
    self.navigationController?.pushViewController(viewController, animated: true)
  }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
