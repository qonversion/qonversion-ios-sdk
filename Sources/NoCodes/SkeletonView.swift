//
//  SkeletonView.swift
//  QonversionNoCodes
//
//  Created by Suren Sarkisyan on 03.04.2025.
//  Copyright © 2025 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)
import UIKit

struct SkeletonViewConstants {
  static let topLayerWidth: CGFloat = 200.0
  static let topLayerHeight: CGFloat = 24.0
  static let topLayerOffset: CGFloat = 105.0
  static let midLayerHeight: CGFloat = 222.0
  static let midLayerTopOffset: CGFloat = 189.0
  static let defaultOffset: CGFloat = 20.0
  static let smallLayerHeight: CGFloat = 14.0
  static let middleSizeLayersBetweenSpace: CGFloat = 9.0
  static let middleSizeLayersTopSpace: CGFloat = 12.0
  static let midContainerViewsSpace: CGFloat = 24.0
  static let midContainerTopOffset: CGFloat = 40.0
  static let botLayerOffset: CGFloat = 8.0
  static let botLayersCount: CGFloat = 3.0
  static let defaultLayerColor = UIColor(red: 223.0/255.0, green: 223.0/255.0, blue: 223.0/255.0, alpha: 1.0)
  static let lightModeAnimationFinish: Float = 0.4
  static let lightModeAnimationStart: Float = 0.7
  static let darkModeAnimationFinish: Float = 0.15
  static let darkModeAnimationStart: Float = 0.25
  static let animationDuration: CGFloat = 0.8
  static let cornerRadius = 4.0
  static let darkModeColor: UIColor = .black
  static let lightModeColor: UIColor = .white
}

class SkeletonView: UIView {
  
  private var botView: UIView
  private var animationLayers: [CALayer] = []
  private var interfaceStyle: UIUserInterfaceStyle = .light
  
  init(frame: CGRect, interfaceStyle: UIUserInterfaceStyle) {
    botView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 0.0, height: SkeletonViewConstants.smallLayerHeight))
    
    super.init(frame: frame)
    self.interfaceStyle = interfaceStyle
    if interfaceStyle == .dark {
      backgroundColor = SkeletonViewConstants.darkModeColor
    } else {
      backgroundColor = SkeletonViewConstants.lightModeColor
    }
    
    let topLayer = CALayer()
    topLayer.frame = CGRect(x: bounds.width / 2.0 - SkeletonViewConstants.topLayerWidth / 2.0, y: SkeletonViewConstants.topLayerOffset, width: SkeletonViewConstants.topLayerWidth, height: SkeletonViewConstants.topLayerHeight)
    let midLayer = CALayer()
    midLayer.frame = CGRect(x: SkeletonViewConstants.defaultOffset, y: SkeletonViewConstants.midLayerTopOffset, width: bounds.width - SkeletonViewConstants.defaultOffset * 2.0, height: SkeletonViewConstants.midLayerHeight)
    animationLayers.append(topLayer)
    animationLayers.append(midLayer)
    layer.addSublayer(topLayer)
    layer.addSublayer(midLayer)
    
    let midLayersViewHeight = SkeletonViewConstants.smallLayerHeight * 2 + SkeletonViewConstants.middleSizeLayersTopSpace
    
    let midLayersTopView = UIView(frame: CGRect(x: 0.0, y: midLayer.frame.maxY + SkeletonViewConstants.midContainerTopOffset, width: bounds.width, height: midLayersViewHeight))
    
    let middleSizeLayerWidth = (bounds.width - SkeletonViewConstants.defaultOffset * 2 - SkeletonViewConstants.middleSizeLayersBetweenSpace) / 2.0
    
    let firstMidSizeLayer = generateMidLayer(position: 1, width: middleSizeLayerWidth)
    let secondMidSizeLayer = generateMidLayer(position: 2, width: middleSizeLayerWidth)
    let thirdMidSizeLayer = generateMidLayer(position: 3, width: middleSizeLayerWidth)
    let fourthMidSizeLayer = generateMidLayer(position: 4, width: middleSizeLayerWidth)
    
    animationLayers.append(firstMidSizeLayer)
    animationLayers.append(secondMidSizeLayer)
    animationLayers.append(thirdMidSizeLayer)
    animationLayers.append(fourthMidSizeLayer)
    
    midLayersTopView.layer.addSublayer(firstMidSizeLayer)
    midLayersTopView.layer.addSublayer(secondMidSizeLayer)
    midLayersTopView.layer.addSublayer(thirdMidSizeLayer)
    midLayersTopView.layer.addSublayer(fourthMidSizeLayer)
    addSubview(midLayersTopView)
    
    let midLayersBotView = UIView(frame: CGRect(x: 0.0, y: midLayersTopView.frame.maxY + SkeletonViewConstants.midContainerViewsSpace, width: bounds.width, height: midLayersViewHeight))
    let fifthMidSizeLayer = generateMidLayer(position: 1, width: middleSizeLayerWidth)
    let sixthMidSizeLayer = generateMidLayer(position: 2, width: middleSizeLayerWidth)
    let seventhMidSizeLayer = generateMidLayer(position: 3, width: middleSizeLayerWidth)
    let eighthMidSizeLayer = generateMidLayer(position: 4, width: middleSizeLayerWidth)
    
    animationLayers.append(fifthMidSizeLayer)
    animationLayers.append(sixthMidSizeLayer)
    animationLayers.append(seventhMidSizeLayer)
    animationLayers.append(eighthMidSizeLayer)
    
    midLayersBotView.layer.addSublayer(fifthMidSizeLayer)
    midLayersBotView.layer.addSublayer(sixthMidSizeLayer)
    midLayersBotView.layer.addSublayer(seventhMidSizeLayer)
    midLayersBotView.layer.addSublayer(eighthMidSizeLayer)
    
    addSubview(midLayersBotView)
    
    botView = UIView(frame: CGRect(x: 0.0, y: safeAreaLayoutGuide.layoutFrame.size.height - SkeletonViewConstants.defaultOffset, width: bounds.width, height: SkeletonViewConstants.smallLayerHeight))
    let botLayerWidth: CGFloat = (bounds.width - SkeletonViewConstants.defaultOffset * 2 - SkeletonViewConstants.botLayerOffset * 2) / SkeletonViewConstants.botLayersCount
    let firstBotLayer = generateBotLayer(position: 1, width: botLayerWidth)
    let secondBotLayer = generateBotLayer(position: 2, width: botLayerWidth)
    let thirdBotLayer = generateBotLayer(position: 3, width: botLayerWidth)
    
    animationLayers.append(firstBotLayer)
    animationLayers.append(secondBotLayer)
    animationLayers.append(thirdBotLayer)
    
    botView.layer.addSublayer(firstBotLayer)
    botView.layer.addSublayer(secondBotLayer)
    botView.layer.addSublayer(thirdBotLayer)
    addSubview(botView)
    
    
    animationLayers.forEach {
      $0.backgroundColor = SkeletonViewConstants.defaultLayerColor.cgColor
      $0.cornerRadius = SkeletonViewConstants.cornerRadius
      $0.masksToBounds = true
      $0.opacity = interfaceStyle == .light ? SkeletonViewConstants.lightModeAnimationStart : SkeletonViewConstants.darkModeAnimationStart
    }
  }
  
  func generateBotLayer(position: Int, width: CGFloat) -> CALayer {
    let xPosition: CGFloat = SkeletonViewConstants.defaultOffset + width * (CGFloat(position) - 1) + SkeletonViewConstants.botLayerOffset * (CGFloat(position) - 1)
    
    let layer = CALayer()
    layer.frame = CGRect(x: xPosition, y: 0.0, width: width, height: SkeletonViewConstants.smallLayerHeight)
    
    return layer
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    botView.frame = CGRect(x: botView.frame.origin.x, y: bounds.height - safeAreaInsets.bottom - SkeletonViewConstants.defaultOffset, width: botView.bounds.width, height: botView.bounds.height)
  }
  
  func generateMidLayer(position: Int, width: CGFloat) -> CALayer {
    var xPosition = SkeletonViewConstants.defaultOffset
    var yPosition = 0.0
    switch position {
    case 1:
      break
    case 2:
      xPosition = xPosition + width + SkeletonViewConstants.middleSizeLayersBetweenSpace
    case 3:
      yPosition = SkeletonViewConstants.smallLayerHeight + SkeletonViewConstants.middleSizeLayersTopSpace
    case 4:
      yPosition = SkeletonViewConstants.smallLayerHeight + SkeletonViewConstants.middleSizeLayersTopSpace
      xPosition = xPosition + width + SkeletonViewConstants.middleSizeLayersBetweenSpace
    default:
      break
    }
    let layer = CAGradientLayer()
    layer.frame = CGRect(x: xPosition, y: yPosition, width: width, height: SkeletonViewConstants.smallLayerHeight)
    
    return layer
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func startAnimation() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
      self.animationLayers.forEach { self.addAnimation(layer: $0) }
    })
  }
  
  func stopAnimation() {
    animationLayers.forEach { $0.removeAllAnimations() }
  }
  
  func addAnimation(layer: CALayer) {
    let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
    animation.fromValue = layer.opacity
    animation.toValue = interfaceStyle == .light ? SkeletonViewConstants.lightModeAnimationFinish : SkeletonViewConstants.darkModeAnimationFinish
    animation.duration = SkeletonViewConstants.animationDuration
    animation.repeatCount = .infinity
    animation.autoreverses = true
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "fade")
  }
  
}

#endif
