//
//  ViewController.swift
//  ARSmartCamera
//
//  Created by Milind Pathiyal on 9/6/19.
//  Copyright © 2019 Milind Pathiyal. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    // SCENE
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.05 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    // COREML
    var visionRequests = [VNRequest]()
    
    //Threading to continuously run requests to CoreML in realtime, and without disturbing ARKit / SceneView
    let dispatchQueueML = DispatchQueue(label: "ThreadingCoreML") // A Serial Queue
    @IBOutlet var debugObjectTextView: UITextView!
    @IBOutlet var debugConfidenceTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.showsStatistics = true
        
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.autoenablesDefaultLighting = true
        
        // Tap Gesture Recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        // Set up Vision Model: Resnet50
        guard let selectedModel = try? VNCoreMLModel(for: Resnet50().model) else {return}
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        
        // Crop & obtain image in center of view
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
        
        visionRequests = [classificationRequest]
        // Begin Loop to Update CoreML to prevent hiccups in Frame Rate
        // Threading to continuously run requests to CoreML in realtime, and without disturbing ARKit / SceneView
        loopCoreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
        }
    }
    
    // Setup AR Text
    @objc func handleTap(gestureRecognize: UITapGestureRecognizer) {
        //Calculate center point of iPhone screen
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint])
        
        if let closestResult = arHitTestResults.first {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create AR Text
            let node : SCNNode = createNewBubbleParentNode(latestPrediction)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldCoord
        }
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE-TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(bubbleDepth))
        var font = UIFont(name: "PingFangSC-Ultralight", size: 0.15)
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        
        //Text follows camera view
        bubble.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        
        bubble.firstMaterial?.diffuse.contents = UIColor.orange
        bubble.firstMaterial?.specular.contents = UIColor.white
        //bubble.firstMaterial?.isDoubleSided = true
        // Setting bubble.flatness too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // Create spherical pin
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // Combine text and spherical pin
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    

    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard request.results != nil else {
            print("No results")
            return
        }
        guard let results = request.results as? [VNClassificationObservation] else {return}
        guard let firstObservation = results.first else {return}
        

        DispatchQueue.main.async {
            
            print("Camera was able to capture a frame", Date())
            print(firstObservation.identifier, firstObservation.confidence)
            print("---")
            
            // Display Object & Confidence Text on screen
            var debugObjectText:String = ""
            debugObjectText += "Object: " + firstObservation.identifier
            self.debugObjectTextView.text = debugObjectText
            
            var debugConfidenceText:String = ""
            debugConfidenceText += "Confidence: " + firstObservation.confidence.description
            self.debugConfidenceTextView.text = debugConfidenceText
            
            // Store the latest prediction
            let delimiter = ","
            let newstr = firstObservation.identifier
            var token = newstr.components(separatedBy: delimiter)
            self.latestPrediction = token[0]
        }
    }
    
    // CoreML Vision Handling
    // Threading to continuously run requests to CoreML in realtime, and without disturbing ARKit / SceneView
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
    }
    
    func updateCoreML() {
        // Get Camera Image as RGB
        // We're using ARKit's ARFrame as the image to be fed into CoreML
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        //CoreML uses CMSampleBufferGetImageBuffer to capture image
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
       
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }
}
extension UIFont {
    func withTraits(traits:UIFontDescriptor.SymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
