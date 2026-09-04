import Foundation

enum DolbyDownmixType {
    case none
    case loRo    // Line out, Reference out
    case ltRt    // Left total, Right total
    case dplII   // Dolby Pro Logic II
}

struct DolbyDownmixParams {
    var type: DolbyDownmixType = .none
    var centerMixLevel: Double = 0.707      // -3dB
    var centerMixLevelLtRt: Double = 0.707
    var surroundMixLevel: Double = 0.707
    var surroundMixLevelLtRt: Double = 0.707
    var lfeMixLevel: Double = 0.0
}

class DolbyDownmixProcessor {
    private var params: DolbyDownmixParams = DolbyDownmixParams()
    private var inputChannelCount: Int = 0
    private var outputChannelCount: Int = 0
    private var active: Bool = false
    
    private var cmix: Float = 0.707
    private var smix: Float = 0.707
    private var lfeMix: Float = 0.0
    private var preferLtRt: Bool = false
    
    func configure(params: DolbyDownmixParams,
                   inputChannelCount: Int,
                   outputChannelCount: Int) -> Bool {
        self.params = params
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.active = false
        
        guard params.type != .none else { return false }
        guard outputChannelCount == 2 else { return false }
        guard inputChannelCount >= 3 else { return false }
        
        cmix = (params.type == .ltRt || params.type == .dplII)
            ? Float(params.centerMixLevelLtRt)
            : Float(params.centerMixLevel)
        smix = (params.type == .ltRt || params.type == .dplII)
            ? Float(params.surroundMixLevelLtRt)
            : Float(params.surroundMixLevel)
        lfeMix = Float(params.lfeMixLevel)
        preferLtRt = (params.type == .ltRt || params.type == .dplII)
        
        active = true
        return true
    }
    
    func isActive() -> Bool { return active }
    func getInputChannelCount() -> Int { return inputChannelCount }
    func getOutputChannelCount() -> Int { return outputChannelCount }
    
    func processFloat32(inputInterleaved: UnsafePointer<Float>,
                        outputInterleaved: UnsafeMutablePointer<Float>,
                        frameCount: Int) {
        guard active else { return }
        
        let inCh = inputChannelCount
        let outCh = outputChannelCount
        
        for i in 0..<frameCount {
            let inPtr = inputInterleaved.advanced(by: i * inCh)
            let outPtr = outputInterleaved.advanced(by: i * outCh)
            processFrameFloat32(input: inPtr, output: outPtr)
        }
    }
    
    func processFloat32Planar(inputPlanes: [UnsafePointer<Float>],
                              outputPlanes: [UnsafeMutablePointer<Float>],
                              frameCount: Int) {
        guard active else { return }
        
        let ch = inputChannelCount
        
        for i in 0..<frameCount {
            let L = inputPlanes[0][i]
            let R = inputPlanes[1][i]
            let C = (ch > 2) ? inputPlanes[2][i] : 0.0
            let LFE = (ch > 3) ? inputPlanes[3][i] : 0.0
            let Ls = (ch > 4) ? inputPlanes[4][i] : 0.0
            let Rs = (ch > 5) ? inputPlanes[5][i] : 0.0
            let Lb = (ch > 6) ? inputPlanes[6][i] : 0.0
            let Rb = (ch > 7) ? inputPlanes[7][i] : 0.0
            
            var outL = L + cmix * C + lfeMix * LFE
            var outR = R + cmix * C + lfeMix * LFE
            
            if preferLtRt {
                outL += smix * Ls - smix * Rs + smix * Lb - smix * Rb
                outR += -smix * Ls + smix * Rs - smix * Lb + smix * Rb
            } else {
                outL += smix * Ls + smix * Lb
                outR += smix * Rs + smix * Rb
            }
            
            outputPlanes[0][i] = outL
            outputPlanes[1][i] = outR
        }
    }
    
    private func processFrameFloat32(input: UnsafePointer<Float>,
                                     output: UnsafeMutablePointer<Float>) {
        let ch = inputChannelCount

        let L = input[0]
        let R = input[1]
        let C = (ch > 2) ? input[2] : 0.0
        let LFE = (ch > 3) ? input[3] : 0.0
        let Ls = (ch > 4) ? input[4] : 0.0
        let Rs = (ch > 5) ? input[5] : 0.0
        let Lb = (ch > 6) ? input[6] : 0.0
        let Rb = (ch > 7) ? input[7] : 0.0

        var outL = L + cmix * C + lfeMix * LFE
        var outR = R + cmix * C + lfeMix * LFE

        if preferLtRt {
            outL += smix * Ls - smix * Rs + smix * Lb - smix * Rb
            outR += -smix * Ls + smix * Rs - smix * Lb + smix * Rb
        } else {
            outL += smix * Ls + smix * Lb
            outR += smix * Rs + smix * Rb
        }

        output[0] = outL
        output[1] = outR
    }
}