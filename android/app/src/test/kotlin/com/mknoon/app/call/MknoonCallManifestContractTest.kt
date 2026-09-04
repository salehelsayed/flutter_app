package com.mknoon.app.call

import com.mknoon.app.BuildConfig
import java.io.File
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Document
import org.w3c.dom.Element

class MknoonCallManifestContractTest {
    @Test
    fun `VC2-04 merged manifest declares protected call components and permissions`() {
        val manifest = mergedManifest()
        val variant = BuildConfig.BUILD_TYPE

        for (permission in REQUIRED_PERMISSIONS) {
            val declarations = manifest.elements("uses-permission")
                .filter { it.androidAttribute("name") == permission }

            assertEquals(
                "$variant merged manifest must declare $permission exactly once",
                1,
                declarations.size,
            )
            assertFalse(
                "$variant merged manifest must not cap $permission with maxSdkVersion",
                declarations.single().hasAndroidAttribute("maxSdkVersion"),
            )
        }

        val application = manifest.uniqueElement("application", variant)
        assertFalse(
            "$variant application must use its default process",
            application.hasAndroidAttribute("process"),
        )

        val service = manifest.uniqueComponent(
            tagName = "service",
            className = CALL_SERVICE,
            variant = variant,
        )
        service.assertExplicitlyNotExported(variant)
        service.assertUsesDefaultProcess(variant)
        assertTrue(
            "$variant $CALL_SERVICE must explicitly declare foregroundServiceType",
            service.hasAndroidAttribute("foregroundServiceType"),
        )
        assertEquals(
            "$variant $CALL_SERVICE foreground-service types",
            setOf("phoneCall", "microphone"),
            service.androidAttribute("foregroundServiceType")
                .split('|')
                .filter(String::isNotBlank)
                .toSet(),
        )

        val receiver = manifest.uniqueComponent(
            tagName = "receiver",
            className = CALL_ACTION_RECEIVER,
            variant = variant,
        )
        receiver.assertExplicitlyNotExported(variant)
        receiver.assertUsesDefaultProcess(variant)
    }

    @Test
    fun `VC2-04 generated BuildConfig keeps Android native calling default off`() {
        assertTrue(
            "contract must run against a debug or release BuildConfig, not ${BuildConfig.BUILD_TYPE}",
            BuildConfig.BUILD_TYPE == "debug" || BuildConfig.BUILD_TYPE == "release",
        )
        assertFalse(
            "${BuildConfig.BUILD_TYPE} BuildConfig must default " +
                "ENABLE_ANDROID_NATIVE_CALLS to false",
            BuildConfig.ENABLE_ANDROID_NATIVE_CALLS,
        )
    }

    @Test
    fun `VC2-05 background ringtone holds only the playback wake lock`() {
        val source = repoFile(
            "android/app/src/main/kotlin/com/mknoon/app/call/MknoonIncomingCallRinger.kt",
        ).readText()

        assertTrue(
            source.contains(
                "player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)",
            ),
        )
    }

    @Test
    fun `VC2-04 build declares the pinned Core Telecom dependency`() {
        val gradle = repoFile("android/app/build.gradle.kts").readText()

        assertTrue(gradle.contains("androidx.core:core-telecom:1.1.0-beta01"))
    }

    @Test
    fun `VC2-04 disposable proof build root is narrow and sentinel protected`() {
        val gradle = repoFile("android/build.gradle.kts").readText()
        val harness = repoFile("scripts/run_vc204_android_call_lifecycle_e2e.sh").readText()

        assertTrue(gradle.contains("vc204ProofBuildRoot"))
        assertTrue(gradle.contains("vc204-proof-gradle-build"))
        assertTrue(gradle.contains(".vc204-proof-build-root"))
        assertTrue(gradle.contains("forbiddenRoots.none"))
        assertFalse(gradle.contains("mknoonBuildRoot"))
        assertTrue(harness.contains("physical_directory()"))
        assertTrue(harness.contains("require_empty_directory \"\$artifact_dir\" \"build-only artifact\""))
        assertTrue(harness.contains("cannot inspect \$label directory contents"))
        assertTrue(harness.contains("pm list packages --user -1"))
        assertTrue(harness.contains("am get-current-user"))
    }

    private fun mergedManifest(): Document {
        val buildType = BuildConfig.BUILD_TYPE
        val variant = buildType.replaceFirstChar(Char::uppercaseChar)
        val manifest = repoFile(
            "build/app/intermediates/merged_manifests/" +
                "$buildType/process${variant}Manifest/AndroidManifest.xml",
        )
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setAttribute(ACCESS_EXTERNAL_DTD, "")
            setAttribute(ACCESS_EXTERNAL_SCHEMA, "")
        }
        return factory.newDocumentBuilder().parse(manifest)
    }

    private fun Document.uniqueComponent(
        tagName: String,
        className: String,
        variant: String,
    ): Element {
        val matches = elements(tagName)
            .filter { it.androidAttribute("name") == className }
        assertEquals(
            "$variant merged manifest must contain exactly one $tagName $className",
            1,
            matches.size,
        )
        return matches.single()
    }

    private fun Document.uniqueElement(tagName: String, variant: String): Element {
        val matches = elements(tagName)
        assertEquals(
            "$variant merged manifest must contain exactly one $tagName element",
            1,
            matches.size,
        )
        return matches.single()
    }

    private fun Document.elements(tagName: String): List<Element> {
        val nodes = getElementsByTagName(tagName)
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun Element.assertExplicitlyNotExported(variant: String) {
        val className = androidAttribute("name")
        assertTrue(
            "$variant $className must explicitly declare android:exported",
            hasAndroidAttribute("exported"),
        )
        assertEquals(
            "$variant $className must not be exported",
            "false",
            androidAttribute("exported"),
        )
    }

    private fun Element.assertUsesDefaultProcess(variant: String) {
        val className = androidAttribute("name")
        assertFalse(
            "$variant $className must not declare an extra process",
            hasAndroidAttribute("process"),
        )
    }

    private fun Element.androidAttribute(name: String): String =
        getAttributeNS(ANDROID_NAMESPACE, name)

    private fun Element.hasAndroidAttribute(name: String): Boolean =
        hasAttributeNS(ANDROID_NAMESPACE, name)

    private fun repoFile(relativePath: String): File {
        val workingDirectory = checkNotNull(System.getProperty("user.dir"))
        return generateSequence(File(workingDirectory).absoluteFile) { current ->
            current.parentFile
        }.map { root -> File(root, relativePath) }
            .firstOrNull(File::isFile)
            ?: error("Cannot locate $relativePath from $workingDirectory")
    }

    private companion object {
        const val ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
        const val ACCESS_EXTERNAL_DTD =
            "http://javax.xml.XMLConstants/property/accessExternalDTD"
        const val ACCESS_EXTERNAL_SCHEMA =
            "http://javax.xml.XMLConstants/property/accessExternalSchema"
        const val CALL_SERVICE = "com.mknoon.app.call.MknoonCallForegroundService"
        const val CALL_ACTION_RECEIVER = "com.mknoon.app.call.MknoonCallActionReceiver"

        val REQUIRED_PERMISSIONS = listOf(
            "android.permission.MANAGE_OWN_CALLS",
            "android.permission.USE_FULL_SCREEN_INTENT",
            "android.permission.FOREGROUND_SERVICE_PHONE_CALL",
            "android.permission.FOREGROUND_SERVICE_MICROPHONE",
            "android.permission.BLUETOOTH_CONNECT",
            "android.permission.WAKE_LOCK",
        )
    }
}
