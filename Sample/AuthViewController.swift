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
import Qonversion

class AuthViewController: UIViewController {
  
  @IBOutlet var signInButton: GIDSignInButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
    
    GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, err in
      if let user = user {
        self?.processUserLogin(user: user)
      }
    }
  }
  
  @IBAction func didTouchSignInButton(_ sender: Any) {
    let conf = GIDConfiguration(clientID: "11599271839-qalspkpqrihnkl1e12be731tgmre5uop.apps.googleusercontent.com")
    GIDSignIn.sharedInstance.signIn(with: conf, presenting: self) { [weak self] user, error in
      guard let user = user else { return }

      self?.processUserLogin(user: user)
    }
  }
  
  func processUserLogin(user: GIDGoogleUser) {
    guard let idToken = user.authentication.idToken else { return }
    
    let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                   accessToken: user.authentication.accessToken)
    
    Auth.auth().signIn(with: credential) { [weak self] authResult, error in
      if let error = error {
        // handle error
      }
      
      guard let uid = authResult?.user.uid else  { return }
      
      Qonversion.shared().identify(uid)
      self?.showMainScreen()
    }
  }
  
  func showMainScreen() {
    let viewController = self.storyboard?.instantiateViewController(withIdentifier: "MainViewController") as! ViewController
    
    self.navigationController?.pushViewController(viewController, animated: true)
  }
}
