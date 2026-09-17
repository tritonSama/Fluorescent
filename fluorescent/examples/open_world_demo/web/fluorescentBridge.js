window.fluorescentBridge = {
    initCanvas: function(canvasId) {
        return new Promise((resolve, reject) => {
            console.log('Fluorescent WebGPU mock initialized on ID:', canvasId);
            const canvas = document.createElement('canvas');
            canvas.id = canvasId;
            canvas.style.position = 'absolute';
            canvas.style.top = '0';
            canvas.style.left = '0';
            canvas.style.width = '100%';
            canvas.style.height = '100%';
            canvas.style.zIndex = '-1';
            document.body.appendChild(canvas);

            // Mock an open world rendering
            const ctx = canvas.getContext('2d');
            let t = 0;
            function draw() {
                canvas.width = window.innerWidth;
                canvas.height = window.innerHeight;
                
                // Sky
                const grad = ctx.createLinearGradient(0, 0, 0, canvas.height/2);
                grad.addColorStop(0, '#87CEEB'); // Sky blue
                grad.addColorStop(1, '#E0F6FF'); // Horizon
                ctx.fillStyle = grad;
                ctx.fillRect(0, 0, canvas.width, canvas.height/2);

                // Ground
                ctx.fillStyle = '#228B22'; // Forest green
                ctx.fillRect(0, canvas.height/2, canvas.width, canvas.height/2);

                // A moving "sun" or "cloud"
                ctx.fillStyle = '#FFD700';
                ctx.beginPath();
                ctx.arc(100 + Math.sin(t)*50, 100, 40, 0, Math.PI*2);
                ctx.fill();

                // Fake 3D grid lines on the ground to look cool
                ctx.strokeStyle = '#1a6b1a';
                ctx.lineWidth = 2;
                ctx.beginPath();
                for(let i=0; i<canvas.width; i+=50) {
                    ctx.moveTo(canvas.width/2, canvas.height/2);
                    ctx.lineTo(i - (t*100)%50, canvas.height);
                }
                
                // FIXED: Avoid infinite loop by making step size at least 1!
                for(let i=canvas.height/2; i<canvas.height; i+= Math.max(1, (i - canvas.height/2)/5)) {
                    ctx.moveTo(0, i + (t*5)%10);
                    ctx.lineTo(canvas.width, i + (t*5)%10);
                }
                ctx.stroke();

                t += 0.05;
                requestAnimationFrame(draw);
            }
            draw();

            resolve(true);
        });
    }
};
