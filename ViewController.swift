import UIKit
import SceneKit
import ARKit

// SCNVector3 Extension for subtraction and cross-product
extension SCNVector3 {
    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }
    
    func cross(_ vector: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            y * vector.z - z * vector.y,
            z * vector.x - x * vector.z,
            x * vector.y - y * vector.x
        )
    }
    
    var length: Float {
        return sqrt(x * x + y * y + z * z)
    }
}

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    
    var dotNodes = [SCNNode]()
    var textNode = SCNNode()
    var lineNode = SCNNode()
    var measurementMode: MeasurementMode = .distance
    let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    enum MeasurementMode {
        case distance
        case area
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        impactFeedbackGenerator.prepare()
        setupUI()
    }
    
    func setupUI() {
        let toolbarHeight: CGFloat = 50
        let bottomPadding = view.safeAreaInsets.bottom  // Get safe area padding for proper placement
        let yOffset = self.view.frame.size.height - toolbarHeight - bottomPadding - 10  // Move it up slightly

        let toolbar = UIToolbar(frame: CGRect(x: 0, y: yOffset, width: self.view.frame.size.width, height: toolbarHeight))
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let distanceButton = UIBarButtonItem(title: "Distance", style: .plain, target: self, action: #selector(setDistanceMode))
        let areaButton = UIBarButtonItem(title: "Area", style: .plain, target: self, action: #selector(setAreaMode))
        let resetButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(resetMeasurement))
        
        toolbar.setItems([distanceButton, flexSpace, areaButton, flexSpace, resetButton], animated: false)
        self.view.addSubview(toolbar)
    }
    
    @objc func setDistanceMode() {
        measurementMode = .distance
        resetMeasurement()
    }
    
    @objc func setAreaMode() {
        measurementMode = .area
        resetMeasurement()
    }
    
    @objc func resetMeasurement() {
        dotNodes.forEach { $0.removeFromParentNode() }
        dotNodes.removeAll()
        textNode.removeFromParentNode()
        lineNode.removeFromParentNode()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touchLocation = touches.first?.location(in: sceneView) {
            switch measurementMode {
            case .distance:
                handleDistanceMeasurement(at: touchLocation)
            case .area:
                handleAreaMeasurement(at: touchLocation)
            }
        }
    }
    
    func handleDistanceMeasurement(at touchLocation: CGPoint) {
        if dotNodes.count >= 2 {
            resetMeasurement()
        }
        let hitTestResults = sceneView.hitTest(touchLocation, types: .featurePoint)
        if let hitResult = hitTestResults.first {
            addDot(at: hitResult)
            impactFeedbackGenerator.impactOccurred()
        }
    }
    
    func handleAreaMeasurement(at touchLocation: CGPoint) {
        if dotNodes.count >= 4 {
            resetMeasurement()
        }
        let hitTestResults = sceneView.hitTest(touchLocation, types: .featurePoint)
        if let hitResult = hitTestResults.first {
            addDot(at: hitResult)
            impactFeedbackGenerator.impactOccurred()
            if dotNodes.count >= 3 {
                calculateArea()
            }
        }
    }
    
    func addDot(at hitResult: ARHitTestResult) {
        let dotGeometry = SCNSphere(radius: 0.005)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        dotGeometry.materials = [material]
        
        let dotNode = SCNNode(geometry: dotGeometry)
        dotNode.position = SCNVector3(
            hitResult.worldTransform.columns.3.x,
            hitResult.worldTransform.columns.3.y,
            hitResult.worldTransform.columns.3.z
        )
        
        sceneView.scene.rootNode.addChildNode(dotNode)
        dotNodes.append(dotNode)
        updateLines()
        
        if measurementMode == .distance && dotNodes.count == 2 {
            calculateDistance()
        }
    }
    
    func updateLines() {
        lineNode.removeFromParentNode()
        guard dotNodes.count > 1 else { return }
        
        let vertices = dotNodes.map { $0.position }
        let indices: [Int32] = Array(0..<Int32(vertices.count))
        
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let lineGeometry = SCNGeometry(sources: [source], elements: [element])
        
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = UIColor.green
        lineGeometry.materials = [lineMaterial]
        
        lineNode = SCNNode(geometry: lineGeometry)
        sceneView.scene.rootNode.addChildNode(lineNode)
    }
    
    func calculateDistance() {
        let start = dotNodes[0].position
        let end = dotNodes[1].position
        let distance = (end - start).length * 100  // Convert to cm
        
        let formattedDistance = String(format: "%.2f cm", abs(distance))
        updateText(text: formattedDistance, atPosition: end)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    func calculateArea() {
        guard dotNodes.count >= 3 else { return }
        
        var totalArea: Float = 0.0
        let origin = dotNodes[0].position
        
        for i in 1..<(dotNodes.count - 1) {
            let v1 = dotNodes[i].position - origin
            let v2 = dotNodes[i+1].position - origin
            
            let crossProduct = v1.cross(v2)
            let triangleArea = 0.5 * crossProduct.length
            totalArea += triangleArea
        }
        
        totalArea *= 10000  // Convert m² to cm²
        
        var midpoint = SCNVector3Zero
        for dot in dotNodes {
            midpoint.x += dot.position.x
            midpoint.y += dot.position.y
            midpoint.z += dot.position.z
        }
        midpoint.x /= Float(dotNodes.count)
        midpoint.y /= Float(dotNodes.count)
        midpoint.z /= Float(dotNodes.count)
        
        let formattedArea = String(format: "%.2f cm²", totalArea)
        updateText(text: formattedArea, atPosition: midpoint)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    func updateText(text: String, atPosition position: SCNVector3) {
        textNode.removeFromParentNode()
        
        let textGeometry = SCNText(string: text, extrusionDepth: 1.0)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.red
        
        textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(position.x, position.y + 0.01, position.z)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        
        sceneView.scene.rootNode.addChildNode(textNode)
    }
}
