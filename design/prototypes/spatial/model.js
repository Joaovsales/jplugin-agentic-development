(function () {
  const mount = document.getElementById('model-canvas');
  const status = document.getElementById('model-status');
  if (!mount || !window.THREE) {
    if (status) status.textContent = '3D viewer unavailable. The source reference and structure notes remain below.';
    return;
  }

  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#dce3df');
  const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 100);
  camera.position.set(6.4, 5.1, 7.5);
  camera.lookAt(0, 0.2, 0);
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputEncoding = THREE.sRGBEncoding;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.82;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  mount.appendChild(renderer.domElement);

  const metal = (color, roughness = 0.65) => new THREE.MeshStandardMaterial({ color, metalness: 0.35, roughness });
  const shell = metal('#0b1517');
  const deck = metal('#1b2a2d');
  const dark = metal('#111c1f', 0.8);
  const rim = metal('#9aafae', 0.46);
  const copper = metal('#bd8255', 0.45);
  const copperLight = metal('#e4b782', 0.43);
  const teal = metal('#88a9a5', 0.46);
  const model = new THREE.Group();
  scene.add(model);

  function box(width, height, depth, material, x, y, z) {
    const part = new THREE.Mesh(new THREE.BoxGeometry(width, height, depth), material);
    part.position.set(x, y, z);
    part.castShadow = true;
    part.receiveShadow = true;
    model.add(part);
    return part;
  }

  function rail(points, radius, material) {
    const curve = new THREE.CatmullRomCurve3(points.map(point => new THREE.Vector3(...point)));
    const part = new THREE.Mesh(new THREE.TubeGeometry(curve, 28, radius, 6, false), material);
    part.castShadow = true;
    model.add(part);
  }

  // Blockout: one shallow enclosure; the copper selector is a separate assembly.
  box(5.8, 1.25, 2.9, shell, 0, 0, 0);
  box(5.7, 0.09, 2.8, deck, 0, 0.67, 0);
  box(5.75, 0.035, 0.025, rim, 0, 0.73, 1.38);
  box(5.75, 0.035, 0.025, rim, 0, 0.73, -1.38);
  box(0.025, 0.035, 2.76, rim, -2.83, 0.73, 0);
  box(0.025, 0.035, 2.76, rim, 2.83, 0.73, 0);
  box(0.58, 0.66, 0.62, copper, 1.02, 1.04, -0.55);
  box(0.6, 0.045, 0.64, copperLight, 1.02, 1.39, -0.55);
  box(0.28, 0.008, 0.2, dark, 1.02, 1.418, -0.55);

  // Three deck inputs converge on the selector; one copper route leaves it.
  [-0.9, -0.25, 0.4].forEach((z, index) => {
    const path = [[-2.35, 0.77, z], [-0.9, 0.77, z], [0.72, 0.77, -0.55]];
    rail(path, 0.07, dark);
    rail(path.map(([x, y, zz]) => [x, y + 0.058, zz]), 0.017, index === 2 ? copperLight : teal);
  });
  rail([[1.32, 0.77, -0.55], [2.45, 0.77, -0.55]], 0.07, dark);
  rail([[1.32, 0.83, -0.55], [2.45, 0.83, -0.55]], 0.019, copperLight);

  // Recessed front sockets and their contact traces.
  [-1.95, -0.92, 0.11].forEach(x => {
    box(0.57, 0.37, 0.012, dark, x, -0.08, 1.459);
    box(0.37, 0.018, 0.014, teal, x, 0.02, 1.47);
  });
  box(0.68, 0.42, 0.012, dark, 2.06, -0.04, 1.459);
  box(0.39, 0.025, 0.014, copperLight, 2.06, -0.01, 1.47);
  [[-2.55, 1.15], [2.55, 1.15], [-2.55, -1.15], [2.55, -1.15]].forEach(([x, z]) => {
    const screw = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.012, 12), rim);
    screw.position.set(x, 0.728, z);
    model.add(screw);
  });

  const floor = new THREE.Mesh(new THREE.PlaneGeometry(200, 200), new THREE.ShadowMaterial({ opacity: 0.19 }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -0.76;
  floor.receiveShadow = true;
  scene.add(floor);
  scene.add(new THREE.HemisphereLight('#ffffff', '#596967', 0.8));
  const sun = new THREE.DirectionalLight('#fff5e9', 1.45);
  sun.position.set(-3, 9, 7);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  sun.shadow.camera.left = -7;
  sun.shadow.camera.right = 7;
  sun.shadow.camera.top = 7;
  sun.shadow.camera.bottom = -7;
  scene.add(sun);

  function render() { renderer.render(scene, camera); }
  function resize() {
    const width = Math.max(1, mount.clientWidth);
    const height = Math.max(1, mount.clientHeight);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    render();
  }
  new ResizeObserver(resize).observe(mount);
  resize();

  const views = {
    reference: [6.4, 5.1, 7.5],
    front: [0, 2.3, 8.5],
    top: [0, 9.5, 0.01]
  };
  document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => {
    camera.position.set(...views[button.dataset.view]);
    camera.lookAt(0, 0.2, 0);
    document.querySelectorAll('[data-view]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    render();
  }));
  status.textContent = 'Live procedural Three.js model. Use the view controls to inspect its depth and sockets.';
})();
