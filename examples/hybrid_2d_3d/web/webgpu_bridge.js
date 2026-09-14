// WebGPU Bridge for Fluorescent Flutter Web Integration

const wgslShaders = `
@vertex
fn vertexMain(@builtin(vertex_index) vertexIndex : u32) -> @builtin(position) vec4<f32> {
  var pos = array<vec2<f32>, 3>(
    vec2<f32>(0.0, 0.5),
    vec2<f32>(-0.5, -0.5),
    vec2<f32>(0.5, -0.5)
  );
  return vec4<f32>(pos[vertexIndex], 0.0, 1.0);
}

@fragment
fn fragmentMain() -> @location(0) vec4<f32> {
  return vec4<f32>(1.0, 0.0, 0.0, 1.0); // Red
}
`;

class FluorescentWebGPUBridge {
    constructor(canvasElementId) {
        this.canvasId = canvasElementId;
        this.canvas = null;
        this.adapter = null;
        this.device = null;
        this.context = null;
        this.pipeline = null;
    }

    async init() {
        this.canvas = document.getElementById(this.canvasId);
        if (!this.canvas) {
            console.error(`FluorescentWebGPUBridge: Canvas with id '${this.canvasId}' not found.`);
            return false;
        }

        if (!navigator.gpu) {
            console.error("FluorescentWebGPUBridge: WebGPU is not supported in this browser.");
            // Fallback to WebGL2 would happen here
            return false;
        }

        try {
            this.adapter = await navigator.gpu.requestAdapter();
            if (!this.adapter) {
                console.error("FluorescentWebGPUBridge: Failed to get WebGPU adapter.");
                return false;
            }

            this.device = await this.adapter.requestDevice();
            this.context = this.canvas.getContext('webgpu');

            const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
            this.context.configure({
                device: this.device,
                format: presentationFormat,
                alphaMode: 'premultiplied',
            });

            // Initialize Pipeline
            const shaderModule = this.device.createShaderModule({
                code: wgslShaders
            });

            this.pipeline = this.device.createRenderPipeline({
                layout: 'auto',
                vertex: {
                    module: shaderModule,
                    entryPoint: 'vertexMain',
                },
                fragment: {
                    module: shaderModule,
                    entryPoint: 'fragmentMain',
                    targets: [{ format: presentationFormat }],
                },
                primitive: {
                    topology: 'triangle-list',
                },
            });

            console.log("FluorescentWebGPUBridge: Successfully initialized WebGPU graphics pipeline.");

            this._renderLoop();
            return true;

        } catch (e) {
            console.error("FluorescentWebGPUBridge: Initialization error: ", e);
            return false;
        }
    }

    _renderLoop() {
        if (!this.device || !this.context || !this.pipeline) return;

        const commandEncoder = this.device.createCommandEncoder();
        const textureView = this.context.getCurrentTexture().createView();

        const renderPassDescriptor = {
            colorAttachments: [
                {
                    view: textureView,
                    clearValue: { r: 0.1, g: 0.1, b: 0.1, a: 1.0 }, // Dark gray clear color
                    loadOp: 'clear',
                    storeOp: 'store',
                },
            ],
        };

        const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
        passEncoder.setPipeline(this.pipeline);
        passEncoder.draw(3); // Draw 3 vertices
        passEncoder.end();

        this.device.queue.submit([commandEncoder.finish()]);

        requestAnimationFrame(() => this._renderLoop());
    }
}

// Attach to window object for Dart JS interop
window.fluorescentBridge = {
    initCanvas: async function(canvasId) {
        const bridge = new FluorescentWebGPUBridge(canvasId);
        return await bridge.init();
    }
};
