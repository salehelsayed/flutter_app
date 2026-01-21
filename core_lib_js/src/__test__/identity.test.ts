import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';
import { IdentityJson } from '../types/identity';

describe('JS_XS_01 - IdentityJson Type', () => {
  it('should have correct shape', () => {
    const identity: IdentityJson = {
      peerId: '12D3KooWTest',
      publicKey: 'dGVzdA==',
      privateKey: 'dGVzdA==',
      mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      createdAt: '2025-01-01T00:00:00.000Z',
      updatedAt: '2025-01-01T00:00:00.000Z',
    };

    expect(identity.peerId).toBeDefined();
    expect(identity.publicKey).toBeDefined();
    expect(identity.privateKey).toBeDefined();
    expect(identity.mnemonic12).toBeDefined();
    expect(identity.createdAt).toBeDefined();
    expect(identity.updatedAt).toBeDefined();
  });
});

describe('JS_XS_02 - generateIdentity', () => {
  it('generates valid identity', async () => {
    const identity = await generateIdentity();

    expect(identity.peerId).toBeTruthy();
    expect(identity.peerId.startsWith('12D3KooW')).toBe(true);
    expect(identity.publicKey).toBeTruthy();
    expect(identity.privateKey).toBeTruthy();
    expect(identity.mnemonic12.split(' ').length).toBe(12);
    expect(identity.createdAt).toBeTruthy();
    expect(identity.updatedAt).toBeTruthy();
  });

  it('generates unique identities', async () => {
    const id1 = await generateIdentity();
    const id2 = await generateIdentity();

    expect(id1.peerId).not.toBe(id2.peerId);
    expect(id1.mnemonic12).not.toBe(id2.mnemonic12);
  });
});

describe('JS_XS_03 - restoreIdentityFromMnemonic', () => {
  it('restores identity from valid mnemonic', async () => {
    // First generate an identity
    const original = await generateIdentity();

    // Restore from its mnemonic
    const restored = await restoreIdentityFromMnemonic(original.mnemonic12);

    // Should produce same peerId and keys
    expect(restored.peerId).toBe(original.peerId);
    expect(restored.publicKey).toBe(original.publicKey);
    expect(restored.privateKey).toBe(original.privateKey);
  });

  it('throws on invalid word count', async () => {
    await expect(
      restoreIdentityFromMnemonic('only six words here not twelve')
    ).rejects.toThrow();
  });

  it('throws on invalid mnemonic', async () => {
    await expect(
      restoreIdentityFromMnemonic('invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid invalid')
    ).rejects.toThrow();
  });

  it('is deterministic', async () => {
    const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    
    const id1 = await restoreIdentityFromMnemonic(mnemonic);
    const id2 = await restoreIdentityFromMnemonic(mnemonic);

    expect(id1.peerId).toBe(id2.peerId);
    expect(id1.publicKey).toBe(id2.publicKey);
  });
});
