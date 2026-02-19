/**
 * Simple Node.js test to verify identity generation works.
 * Run with: node test_identity.js
 */

// Polyfill for browser globals that might be missing in Node
if (typeof btoa === 'undefined') {
  global.btoa = (str) => Buffer.from(str, 'binary').toString('base64');
}
if (typeof atob === 'undefined') {
  global.atob = (str) => Buffer.from(str, 'base64').toString('binary');
}

async function runTest() {
  console.log('========================================');
  console.log('Testing Identity Generation (Node.js)');
  console.log('========================================\n');

  try {
    // Dynamic import for ES modules
    const bip39 = await import('bip39');
    const { generateKeyPairFromSeed } = await import('@libp2p/crypto/keys');
    const { peerIdFromPrivateKey } = await import('@libp2p/peer-id');

    console.log('[TEST] Step 1: Generate mnemonic...');
    const mnemonic = bip39.generateMnemonic(128);
    console.log(`[TEST] Mnemonic: ${mnemonic}`);
    console.log(`[TEST] Word count: ${mnemonic.split(' ').length}`);

    console.log('\n[TEST] Step 2: Derive seed from mnemonic...');
    const seedBuffer = await bip39.mnemonicToSeed(mnemonic);
    const seed = new Uint8Array(seedBuffer.buffer, seedBuffer.byteOffset, seedBuffer.byteLength);
    console.log(`[TEST] Seed length: ${seed.length} bytes`);

    console.log('\n[TEST] Step 3: Generate Ed25519 keypair...');
    const keyPair = await generateKeyPairFromSeed('Ed25519', seed.slice(0, 32));
    console.log(`[TEST] KeyPair type: ${keyPair.type}`);

    console.log('\n[TEST] Step 4: Derive peer ID...');
    const peerId = peerIdFromPrivateKey(keyPair);
    console.log(`[TEST] Peer ID: ${peerId.toString()}`);

    console.log('\n[TEST] Step 5: Get raw key bytes...');
    const publicKeyBytes = keyPair.publicKey.raw;
    const privateKeyBytes = keyPair.raw;
    console.log(`[TEST] Public key length: ${publicKeyBytes.length} bytes`);
    console.log(`[TEST] Private key length: ${privateKeyBytes.length} bytes`);

    console.log('\n[TEST] Step 6: Base64 encode (browser-compatible)...');
    // Browser-compatible base64 encoding
    function uint8ArrayToBase64(bytes) {
      let binary = '';
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      return btoa(binary);
    }

    const publicKeyBase64 = uint8ArrayToBase64(publicKeyBytes);
    const privateKeyBase64 = uint8ArrayToBase64(privateKeyBytes);
    console.log(`[TEST] Public key (base64): ${publicKeyBase64.substring(0, 20)}...`);
    console.log(`[TEST] Private key (base64): ${privateKeyBase64.substring(0, 20)}...`);

    console.log('\n========================================');
    console.log('SUCCESS! Identity generation works!');
    console.log('========================================');
    console.log('\nFinal Identity:');
    console.log(JSON.stringify({
      peerId: peerId.toString(),
      publicKey: publicKeyBase64,
      privateKey: privateKeyBase64,
      mnemonic12: mnemonic,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }, null, 2));

  } catch (error) {
    console.error('\n========================================');
    console.error('ERROR! Test failed:');
    console.error('========================================');
    console.error(error);
    process.exit(1);
  }
}

runTest();
