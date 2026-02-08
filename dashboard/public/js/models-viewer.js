// three.js viewer setup and model loading

const modelsViewer = (function () { // eslint-disable-line no-unused-vars
  let scene, camera, renderer, controls;
  let viewerInitialized = false;

  function initViewer() {
    if (viewerInitialized) return;

    const container = document.getElementById('modelViewerCanvas');
    if (!container || typeof window.THREE === 'undefined') return;

    const THREE = window.THREE;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0xffffff);

    camera = new THREE.PerspectiveCamera(50, container.clientWidth / container.clientHeight, 0.1, 1000);
    camera.position.set(3, 2, 3);

    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    renderer.outputEncoding = THREE.sRGBEncoding;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    container.appendChild(renderer.domElement);

    if (window.THREE.OrbitControls) {
      controls = new THREE.OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.05;
    }

    // lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
    scene.add(ambientLight);

    const hemiLight = new THREE.HemisphereLight(0xffffff, 0x444444, 0.5);
    hemiLight.position.set(0, 20, 0);
    scene.add(hemiLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 1.2);
    directionalLight.position.set(5, 10, 7);
    directionalLight.castShadow = true;
    scene.add(directionalLight);

    const fillLight = new THREE.DirectionalLight(0x4488ff, 0.4);
    fillLight.position.set(-5, 3, -5);
    scene.add(fillLight);

    const backLight = new THREE.DirectionalLight(0xffffff, 0.3);
    backLight.position.set(0, 5, -10);
    scene.add(backLight);

    const gridHelper = new THREE.GridHelper(10, 10, 0xcccccc, 0xe0e0e0);
    scene.add(gridHelper);

    const resizeObserver = new ResizeObserver(() => {
      camera.aspect = container.clientWidth / container.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(container.clientWidth, container.clientHeight);
    });
    resizeObserver.observe(container);

    function animate() {
      requestAnimationFrame(animate);
      if (controls) controls.update();
      renderer.render(scene, camera);
    }
    animate();

    viewerInitialized = true;
  }

  function loadModelPreview(url) {
    console.log('[viewer] loadModelPreview called with:', url);
    if (typeof window.THREE === 'undefined') {
      console.warn('[viewer] THREE is undefined, skipping');
      return;
    }
    console.log('[viewer] THREE loaded, GLTFLoader:', !!window.THREE.GLTFLoader, 'OrbitControls:', !!window.THREE.OrbitControls);

    initViewer();

    const THREE = window.THREE;
    const oldModel = scene.getObjectByName('loadedModel');
    if (oldModel) scene.remove(oldModel);

    const emptyState = document.getElementById('modelViewerEmpty');
    if (emptyState) emptyState.style.display = 'none';

    if (window.THREE.GLTFLoader) {
      const loader = new THREE.GLTFLoader();
      console.log('[viewer] loading model from:', url);
      loader.load(
        url,
        (gltf) => {
          console.log('[viewer] model loaded successfully, children:', gltf.scene.children.length);
          const model = gltf.scene;
          model.name = 'loadedModel';

          const box = new THREE.Box3().setFromObject(model);
          const center = box.getCenter(new THREE.Vector3());
          const size = box.getSize(new THREE.Vector3());
          const maxDim = Math.max(size.x, size.y, size.z);
          const scale = 2 / maxDim;
          console.log('[viewer] model bounds:', { size: { x: size.x, y: size.y, z: size.z }, maxDim, scale });

          model.position.sub(center);
          model.scale.setScalar(scale);
          scene.add(model);

          camera.position.set(3, 2, 3);
          camera.lookAt(0, 0, 0);
          if (controls) controls.target.set(0, 0, 0);
        },
        (progress) => {
          if (progress.total) console.log('[viewer] loading progress:', Math.round(progress.loaded / progress.total * 100) + '%');
        },
        (err) => console.error('[viewer] failed to load model:', err)
      );
    } else {
      console.warn('[viewer] GLTFLoader not available');
    }
  }

  function getScene() { return scene; }

  return { initViewer, loadModelPreview, getScene };
})();
