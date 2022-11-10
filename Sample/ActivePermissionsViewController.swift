//
//  ActivePermissionsViewController.swift
//  Sample
//
//  Created by Surik Sarkisyan on 07.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

import UIKit
import Qonversion

class ActivePermissionsViewController: UIViewController {
  
  var permissions: [Qonversion.Entitlement] = []
  
  @IBOutlet weak var tableView: UITableView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    navigationController?.isNavigationBarHidden = false
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    
    navigationController?.isNavigationBarHidden = true
  }
  
}

extension ActivePermissionsViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return permissions.count
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let permission: Qonversion.Entitlement = permissions[indexPath.row]
    
    let cell = tableView.dequeueReusableCell(withIdentifier: "ActivePermissionsTableViewCell", for: indexPath) as! ActivePermissionsTableViewCell
    cell.setup(with: permission)
    
    return cell
  }
  
}
