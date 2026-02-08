// tests for converter service - glb to fbx/obj conversion

const { isConversionNeeded, convertBuffer, checkAssimpInstalled } = require('../server/services/converter');
const { execFile } = require('child_process');
const fs = require('fs');

jest.mock('child_process', () => ({
  execFile: jest.fn(),
}));

jest.mock('fs', () => {
  const actual = jest.requireActual('fs');
  return {
    ...actual,
    promises: {
      mkdir: jest.fn().mockResolvedValue(undefined),
      writeFile: jest.fn().mockResolvedValue(undefined),
      readFile: jest.fn().mockResolvedValue(Buffer.from('converted-data')),
      rm: jest.fn().mockResolvedValue(undefined),
    },
  };
});

// helper to make execFile resolve
function mockExecFileSuccess() {
  execFile.mockImplementation((_cmd, _args, _opts, cb) => {
    if (typeof _opts === 'function') {
      _opts(null, '', '');
    } else if (typeof cb === 'function') {
      cb(null, '', '');
    }
  });
}

// helper to make execFile reject
function mockExecFileFailure(error) {
  execFile.mockImplementation((_cmd, _args, _opts, cb) => {
    if (typeof _opts === 'function') {
      _opts(error);
    } else if (typeof cb === 'function') {
      cb(error);
    }
  });
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('isConversionNeeded', () => {
  test('returns true for meshy with fbx', () => {
    expect(isConversionNeeded('meshy', 'fbx')).toBe(true);
  });

  test('returns true for meshy with obj', () => {
    expect(isConversionNeeded('meshy', 'obj')).toBe(true);
  });

  test('returns true for tripo with fbx', () => {
    expect(isConversionNeeded('tripo', 'fbx')).toBe(true);
  });

  test('returns true for replicate with obj', () => {
    expect(isConversionNeeded('replicate', 'obj')).toBe(true);
  });

  test('returns false for rodin with fbx', () => {
    expect(isConversionNeeded('rodin', 'fbx')).toBe(false);
  });

  test('returns false for rodin with obj', () => {
    expect(isConversionNeeded('rodin', 'obj')).toBe(false);
  });

  test('returns false for any provider with glb', () => {
    expect(isConversionNeeded('meshy', 'glb')).toBe(false);
    expect(isConversionNeeded('tripo', 'glb')).toBe(false);
    expect(isConversionNeeded('rodin', 'glb')).toBe(false);
  });

  test('returns false when format is null or undefined', () => {
    expect(isConversionNeeded('meshy', null)).toBe(false);
    expect(isConversionNeeded('meshy', undefined)).toBe(false);
  });
});

describe('convertBuffer', () => {
  test('calls assimp with correct arguments', async () => {
    mockExecFileSuccess();
    const input = Buffer.from('test-glb-data');

    await convertBuffer(input, 'glb', 'fbx');

    expect(execFile).toHaveBeenCalledWith(
      'assimp',
      ['export', expect.stringContaining('input.glb'), expect.stringContaining('output.fbx')],
      expect.objectContaining({ timeout: 30000 }),
      expect.any(Function)
    );
  });

  test('returns converted buffer', async () => {
    mockExecFileSuccess();
    const input = Buffer.from('test-glb-data');

    const result = await convertBuffer(input, 'glb', 'fbx');

    expect(result).toEqual(Buffer.from('converted-data'));
  });

  test('writes input buffer to temp file', async () => {
    mockExecFileSuccess();
    const input = Buffer.from('test-glb-data');

    await convertBuffer(input, 'glb', 'obj');

    expect(fs.promises.writeFile).toHaveBeenCalledWith(
      expect.stringContaining('input.glb'),
      input
    );
  });

  test('cleans up temp files on success', async () => {
    mockExecFileSuccess();
    const input = Buffer.from('test-glb-data');

    await convertBuffer(input, 'glb', 'fbx');

    expect(fs.promises.rm).toHaveBeenCalledWith(
      expect.stringContaining('model-convert-'),
      { recursive: true, force: true }
    );
  });

  test('cleans up temp files on assimp failure', async () => {
    mockExecFileFailure(new Error('assimp crashed'));
    const input = Buffer.from('test-glb-data');

    await expect(convertBuffer(input, 'glb', 'fbx')).rejects.toThrow('model conversion failed');
    expect(fs.promises.rm).toHaveBeenCalledWith(
      expect.stringContaining('model-convert-'),
      { recursive: true, force: true }
    );
  });

  test('throws 400 for unsupported output format', async () => {
    const input = Buffer.from('test-data');

    try {
      await convertBuffer(input, 'glb', 'stl');
      expect(true).toBe(false); // should not reach
    } catch (err) {
      expect(err.status).toBe(400);
      expect(err.message).toMatch(/unsupported output format/);
    }
  });

  test('includes stderr in error message', async () => {
    const error = new Error('process failed');
    error.stderr = 'unknown format specifier';
    mockExecFileFailure(error);

    const input = Buffer.from('test-data');

    try {
      await convertBuffer(input, 'glb', 'fbx');
      expect(true).toBe(false);
    } catch (err) {
      expect(err.message).toContain('unknown format specifier');
    }
  });

  test('reports timeout when process is killed', async () => {
    const error = new Error('process killed');
    error.killed = true;
    mockExecFileFailure(error);

    const input = Buffer.from('test-data');

    try {
      await convertBuffer(input, 'glb', 'fbx');
      expect(true).toBe(false);
    } catch (err) {
      expect(err.message).toContain('timed out');
    }
  });
});

describe('checkAssimpInstalled', () => {
  test('returns boolean', async () => {
    mockExecFileSuccess();
    const result = await checkAssimpInstalled();
    expect(typeof result).toBe('boolean');
  });
});
