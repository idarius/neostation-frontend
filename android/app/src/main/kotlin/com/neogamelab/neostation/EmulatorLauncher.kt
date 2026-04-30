package com.neogamelab.neostation

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.plugin.common.MethodChannel
import java.io.File

object EmulatorLauncher {

    fun launchGenericIntent(
        context: Context,
        packageName: String,
        activityName: String?,
        action: String?,
        category: String?,
        data: String?,
        type: String?,
        extras: List<Map<String, Any>>?,
        result: MethodChannel.Result
    ) {
        try {
            val intent = Intent()
            if (activityName != null) {
                intent.component = ComponentName(packageName, activityName)
            } else {
                intent.setPackage(packageName)
            }
            intent.action = action ?: Intent.ACTION_MAIN
            
            if (category != null) {
                intent.addCategory(category)
            } else if (action == null || action == Intent.ACTION_MAIN) {
                intent.addCategory(Intent.CATEGORY_LAUNCHER)
            }

            var uriData: Uri? = null
            if (data != null) {
                if (!data.contains("://") && data.startsWith("/")) {
                    // Raw path -> file://
                    uriData = Uri.parse("file://$data")
                } else {
                    uriData = Uri.parse(data)
                }
            }
            
            if (uriData != null && type != null) {
                intent.setDataAndType(uriData, type)
                if (uriData.scheme == "content") {
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
            } else if (uriData != null) {
                intent.data = uriData
                 if (uriData.scheme == "content") {
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
            } else if (type != null) {
                intent.type = type
            }

            // Default Flags: Optimized for clean start
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_CLEAR_TASK)

            // ============================================================================
            // CRITICAL FIX FOR RETROARCH: RESOLVE SAF URI TO REAL FILE PATH
            // ============================================================================
            var resolvedRomPath: String? = null
            
            if (packageName.startsWith("com.retroarch") && extras != null) {
                for (extra in extras) {
                    val key = extra["key"] as? String
                    val value = extra["value"]
                    if (key == "ROM" && value != null) {
                        val romPath = value.toString()
                        if (romPath.startsWith("content://")) {
                            try {
                                val uri = Uri.parse(romPath)
                                resolvedRomPath = resolveSafUriToPath(context, uri)
                                if (resolvedRomPath != null) {
                                    // Resolved
                                } else {
                                    println("EmulatorLauncher: Could not resolve SAF URI to path: $romPath")
                                }
                            } catch (e: Exception) {
                                println("EmulatorLauncher: Error resolution SAF path: ${e.message}")
                            }
                        }
                    }
                }
            }

            // Set Extras
            if (extras != null) {
                for (extra in extras) {
                    val key = extra["key"] as? String
                    val value = extra["value"]
                    val valueType = extra["type"] as? String

                    if (key != null && value != null && valueType != null) {
                        // Use resolved real path if available
                        if (packageName.startsWith("com.retroarch") && key == "ROM") {
                            val targetRomPath = resolvedRomPath ?: value.toString()
                            intent.putExtra(key, targetRomPath)
                        } else {
                            // ============================================================================
                            // STANDALONE EMULATOR FIX (DuckStation, PPSSPP)
                            // ============================================================================
                            
                            var finalValue = value.toString()
                            
                            // SPECIAL: Don't resolve for PPSSPP/Aether/Nether/Citra here, we handle them specifically later
                            val isSpecial = packageName.lowercase().contains("ppsspp") || 
                                          packageName.lowercase().contains("aethersx2") || 
                                          packageName.lowercase().contains("nethersx2") ||
                                          packageName.lowercase().contains("citra") ||
                                          packageName.lowercase().contains("lime3ds") ||
                                          packageName.lowercase().contains("melonds") ||
                                          packageName.lowercase().contains("org.dolphinemu") || 
                                          packageName.lowercase().contains("org.mm.j") || 
                                          packageName.lowercase().contains("org.dolphin.ishiiruka") ||
                                          packageName.lowercase().contains("mupen64plusae") ||
                                          packageName.lowercase().contains("aps3e") ||
                                          packageName.lowercase().contains("info.cemu.cemu")

                            if (!isSpecial && (finalValue.contains("content%3A") || finalValue.contains("content%3a") || finalValue.startsWith("content://"))) {
                                 try {
                                    var uriStr = finalValue
                                    // Decode if needed
                                    if (uriStr.contains("%3A") || uriStr.contains("%3a")) {
                                        uriStr = Uri.decode(uriStr)
                                    }
                                    
                                    if (uriStr.startsWith("content://")) {
                                        val uri = Uri.parse(uriStr)
                                        val real = resolveSafUriToPath(context, uri)
                                        if (real != null) {
                                            // For DuckStation/PPSSPP, we usually want the decoded path
                                            finalValue = Uri.decode(real) 
                                        }
                                    }
                                 } catch (e: Exception) { }
                            }

                            // SPECIAL: DuckStation bootPath collision fix
                            if (packageName.lowercase().contains("duckstation") && key == "bootPath") {
                                 // If we have a bootPath extra, we might need to clear data 
                                 // But let the specific check below handle strict mode clearing if needed
                                 intent.putExtra(key, finalValue)
                            } else if (packageName.lowercase().contains("ppsspp") && key == "org.ppsspp.ppsspp.Args") {
                                 intent.putExtra(key, finalValue)
                            } else {
                                // Generic Handling
                                if (packageName.startsWith("com.retroarch") && key == "LIBRETRO") {
                                    var coreValue = finalValue
                                    if (!coreValue.startsWith("/")) {
                                        val libretroDir = getDefaultLibretroDirectory(packageName)
                                        // User specifically said suffix is _libretro_android.so
                                        if (!coreValue.endsWith("_libretro_android.so")) {
                                            if (coreValue.endsWith("_libretro.so")) {
                                                coreValue = coreValue.replace("_libretro.so", "_libretro_android.so")
                                            } else {
                                                coreValue = "${coreValue}_libretro_android.so"
                                            }
                                        }
                                        finalValue = "$libretroDir$coreValue"
                                    }
                                }

                                when (valueType) {
                                    "string" -> intent.putExtra(key, finalValue)
                                    "bool" -> intent.putExtra(key, finalValue.toBoolean())
                                    "int" -> intent.putExtra(key, finalValue.toIntOrNull() ?: 0)
                                    "long" -> intent.putExtra(key, finalValue.toLongOrNull() ?: 0L)
                                    "float" -> intent.putExtra(key, finalValue.toFloatOrNull() ?: 0.0f)
                                    "uri" -> intent.putExtra(key, Uri.parse(finalValue))
                                    "string_array" -> {
                                        val array = finalValue.split(",").map { it.trim() }.toTypedArray()
                                        intent.putExtra(key, array)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // SPECIAL: DuckStation sometimes needs clear Data
            if (packageName.lowercase().contains("duckstation")) {
                // Ensure no conflict if bootPath is set
                if (intent.hasExtra("bootPath")) {
                    intent.data = null
                }
            }

            // ============================================================================
            // STRICTMODE HACK: Allow passing file:// URIs exposed in Intent Data
            // ============================================================================
            try {
                val m = android.os.StrictMode::class.java.getMethod("disableDeathOnFileUriExposure")
                m.invoke(null)
            } catch (e: Exception) {
                // Ignore
            }

            // SPECIAL: PPSSPP & AetherSX2/NetherSX2 & Lime3DS/Citra & MelonDS & Switch (Eden/Yuzu/Sudachi/Citron) & Dolphin & Mupen64Plus
            val isPPSSPP = packageName.lowercase().contains("ppsspp")
            val isAether = packageName.lowercase().contains("aethersx2") || packageName.lowercase().contains("nethersx2")
            val isCitra = packageName.lowercase().contains("citra") || packageName.lowercase().contains("lime3ds")
            val isMelonDS = packageName.lowercase().contains("melonds")
            val isSwitch = packageName.lowercase().contains("eden") || 
                           packageName.lowercase().contains("yuzu") || 
                           packageName.lowercase().contains("sudachi") || 
                           packageName.lowercase().contains("citron") ||
                           packageName == "com.miHoYo.Yuanshen"
            val isDolphinOfficial = packageName == "org.dolphinemu.dolphinemu" || packageName == "org.dolphinemu.handheld"
            val isDolphinFork = packageName == "org.mm.jr" || packageName == "org.mm.j" || 
                               packageName == "org.dolphinemu.mmjr" || packageName == "org.dolphin.ishiirukadark"
            val isDolphin = isDolphinOfficial || isDolphinFork
            val isMupenModern = packageName.startsWith("org.mupen64plusae.v3")
            val isMupenLegacy = packageName == "paulscode.android.mupen64plusae"
            val isMupen = isMupenModern || isMupenLegacy
            
            val isAPS3E = packageName == "aenu.aps3e"
            val isCemu = packageName.lowercase().contains("info.cemu.cemu")
            
            if (isPPSSPP || isAether || isCitra || isMelonDS || isSwitch || isDolphin || isMupen || isAPS3E || isCemu) {
                var targetPath: String? = null
                
                // 1. Try to get path from existing resolution (Args or bootPath or uri)
                if (intent.hasExtra("org.ppsspp.ppsspp.Args")) {
                    targetPath = intent.getStringExtra("org.ppsspp.ppsspp.Args")
                } else if (intent.hasExtra("bootPath")) {
                    targetPath = intent.getStringExtra("bootPath")
                } else if (intent.hasExtra("iso_uri")) {
                    targetPath = intent.getStringExtra("iso_uri")
                } else if (intent.hasExtra("path")) {
                    targetPath = intent.getStringExtra("path")
                } else if (intent.hasExtra("uri")) {
                    targetPath = intent.getStringExtra("uri")
                    if (targetPath == null && intent.getParcelableExtra<Uri>("uri") != null) {
                        targetPath = intent.getParcelableExtra<Uri>("uri").toString()
                    }
                }
                
                // 2. If not found, try to resolve from current Data
                if (targetPath == null) {
                    var dataStr = intent.dataString
                    if (dataStr != null) {
                         // Check if encoded
                         if (dataStr.contains("%3A") || dataStr.contains("%3a")) {
                             try { dataStr = Uri.decode(dataStr) } catch(e: Exception){}
                         }
                         
                         if (dataStr?.startsWith("content://") == true) {
                             // FIX: Only resolve to File Path if we need it (PPSSPP/Aether/DolphinForks/MupenLegacy)
                             // Citra/Lime3DS, MelonDS, Switch, Official Dolphin, Modern Mupen and aPS3e want the SAF content URI itself
                             if (isCitra || isMelonDS || isSwitch || isDolphinOfficial || isMupenModern || isAPS3E || isCemu) {
                                  targetPath = dataStr
                             } else {
                                 val uri = Uri.parse(dataStr)
                                 targetPath = resolveSafUriToPath(context, uri)
                             }
                         }
                    }
                }
                
                // CRITICAL FIX: Ensure targetPath is resolved to a File Path if it's still a content URI
                // BUT ONLY for emulators that need File Path (PPSSPP).
                // Aether/Nether uses Pure URI launching for Android < 13
                val needsFilePath = isPPSSPP
                
                if (needsFilePath && targetPath != null && targetPath!!.startsWith("content://")) {
                     val resolved = resolveSafUriToPath(context, Uri.parse(targetPath))
                     if (resolved != null) {
                         targetPath = resolved
                     }
                }
                
                if (targetPath != null) {
                     val decodedPath = Uri.decode(targetPath)
                     
                     if (isPPSSPP) {
                         // PPSSPP: ACTION_VIEW + data=file:// + type=application/octet-stream
                         val fileUser = File(decodedPath)
                         val fileUri = Uri.fromFile(fileUser)
                         
                         intent.action = Intent.ACTION_VIEW
                         intent.setDataAndType(fileUri, "application/octet-stream")
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                         intent.putExtra("org.ppsspp.ppsspp.Args", decodedPath)
                     }
                     
                     if (isAether) {
                         // AetherSX2/NetherSX2: ACTION_MAIN + bootPath (String) + No Data
                         val finalBootPath = if (targetPath.startsWith("content://")) targetPath else decodedPath
                         
                         intent.action = Intent.ACTION_MAIN
                         intent.data = null // Clear data to avoid "file not found" from content URI
                         intent.putExtra("bootPath", finalBootPath)
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                         
                         // Fix permission for Android < 13
                         if (targetPath.startsWith("content://")) {
                             val clipData = android.content.ClipData.newRawUri("ROM", Uri.parse(targetPath))
                             intent.clipData = clipData
                             intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                         }
                     }
                     
                     if (isCitra) {
                         // Lime3DS/Citra: Try SAF content:// URI first (Modern Android way)
                         
                         val contentUri = Uri.parse(targetPath) // Should be content:// or file://
                         
                         intent.action = Intent.ACTION_VIEW
                         intent.setDataAndType(contentUri, "*/*") // MIME type might be needed
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                         intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                     }
                     
                     if (isMelonDS) {
                         // MelonDS (beta 1.9.0+)
                         // ... (Same logic as before) ...
                         
                         var finalUri = targetPath
                         
                         // Try to dynamically adjust the Tree URI to point to the specific ROM folder
                         // This is needed because MelonDS often requires the tree root to match the ROM's parent folder
                         try {
                              val treeRegex = "(/tree/[^/]+)(/document/)(.*)".toRegex()
                              val match = treeRegex.find(finalUri)
                              if (match != null) {
                                  val treePart = match.groupValues[1]       // /tree/<TreeID>
                                  val docPart = match.groupValues[3]        // <DocID> (e.g. primary%3AROMs%2Fnds%2Fgame.nds)
                                  
                                  // Find the parent folder of the document
                                  // We look for the last encoded slash (%2F) to strip the filename
                                  val lastSlashIndex = docPart.lastIndexOf("%2F")
                                  if (lastSlashIndex != -1) {
                                      val parentDocId = docPart.substring(0, lastSlashIndex)
                                      
                                      // Construct the new Tree Part using the Parent Document ID
                                      // This effectively "promotes" the tree root to the folder containing the ROM
                                      val newTreePart = "/tree/$parentDocId"
                                      
                                      if (treePart != newTreePart) {
                                          finalUri = finalUri.replace(treePart, newTreePart)
                                      }
                                  }
                              }
                         } catch (e: Exception) {
                               println("EmulatorLauncher: Error adjusting MelonDS URI: ${e.message}")
                         }
                         
                         intent.action = "me.magnum.melonds.LAUNCH_ROM"
                         intent.putExtra("uri", finalUri)
                         
                         // Clear Data/Type
                         intent.setDataAndType(null, null)
                         
                         // CRITICAL: DO NOT SET CLIPDATA.
                         intent.clipData = null
                         
                         // Flags: NEW_TASK + GRANT_READ
                         intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                     }

                     if (isSwitch) {
                         val contentUri = Uri.parse(targetPath) 
                         
                         if (action == "android.nfc.action.TECH_DISCOVERED") {
                             intent.action = action
                         }
                         
                         // Set Data and Type (MIME */*)
                         intent.setDataAndType(contentUri, "*/*") 
                         
                         // FIX: Add ClipData to ensure permissions propagate correctly
                         val clipData = android.content.ClipData.newRawUri("ROM", contentUri)
                         intent.clipData = clipData
                         
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                         intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                         intent.addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                     }

                     if (isDolphin) {
                         val contentUri = Uri.parse(targetPath)
                         
                         // Use ACTION_VIEW as defined in gc.json/wii.json
                         intent.action = Intent.ACTION_VIEW
                         
                         if (isDolphinFork) {
                             // Forks often need the absolute file path and AutoStartFile extra
                             val decodedPath = Uri.decode(targetPath)
                             
                             if (targetPath.startsWith("content://")) {
                                 val resolved = resolveSafUriToPath(context, contentUri)
                                 if (resolved != null) {
                                     intent.putExtra("AutoStartFile", resolved)
                                 } else {
                                     intent.putExtra("AutoStartFile", decodedPath)
                                 }
                             } else {
                                 intent.putExtra("AutoStartFile", decodedPath)
                             }
                         }

                         // Set Data and Type (*/*)
                         intent.setDataAndType(contentUri, "*/*")
                         
                         // For SAF URIs, we MUST grant permissions and add ClipData
                         if (targetPath.startsWith("content://")) {
                             val clipData = android.content.ClipData.newRawUri("ROM", contentUri)
                             intent.clipData = clipData
                             intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                         }
                         
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                     }

                     if (isMupen) {
                         val contentUri = Uri.parse(targetPath)
                         
                         // Use ACTION_VIEW as defined in n64.json
                         intent.action = Intent.ACTION_VIEW
                         
                         // Set Data and Type
                         intent.setDataAndType(contentUri, "*/*")
                         
                         // For SAF URIs (Modern Mupen), we grant permissions and add ClipData
                         if (targetPath.startsWith("content://")) {
                             val clipData = android.content.ClipData.newRawUri("ROM", contentUri)
                             intent.clipData = clipData
                             intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                         } else if (isMupenLegacy) {
                             // Legacy Mupen usually expects a file:// URI or direct path in Data
                             // resolveSafUriToPath should have provided a path already
                             intent.setDataAndType(Uri.fromFile(java.io.File(targetPath)), "*/*")
                         }
                         
                         intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                     }
 
                     if (isAPS3E) {
                         val cleanedPath = cleanUri(targetPath!!)
                         val contentUri = Uri.parse(cleanedPath)
                         
                         // Correct action for aPS3e
                         intent.action = action ?: "aenu.intent.action.APS3E"
                         
                         // flags: NEW_TASK + GRANT_READ + PERSISTABLE + PREFIX
                         intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                         Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                         Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                         Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                          
                         // CRITICAL: Set ClipData for permission propagation (label "ROM")
                         intent.clipData = android.content.ClipData.newRawUri("ROM", contentUri)
                          
                         // aPS3e does NOT want data field set
                         intent.data = null
 
                         // CRITICAL: aPS3e expects the URI in the iso_uri extra
                         intent.putExtra("iso_uri", cleanedPath)
                     }

                     if (isCemu) {
                         // Clean SAF URI path (DO NOT DECODE as it mangles the document ID)
                         val contentUri = Uri.parse(targetPath ?: "")
                         
                         // Cemu Android 0.3 handles ACTION_VIEW with content URI
                         intent.data = contentUri
                         
                         // CRITICAL: Set ClipData for permission propagation (label "ROM")
                         if (targetPath?.startsWith("content://") == true) {
                             val clipData = android.content.ClipData.newRawUri("ROM", contentUri)
                             intent.clipData = clipData
                             intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                             intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                         }
                     }
                }
            }
            
            // Note: If we have a resolved path, we theoretically don't need Intent Data with permissions
            // because RetroArch opens the file directly. BUT keeping it doesn't hurt and helps
            // if resolution fails (fallback to old behavior if I keep the old logic active for null resolvedPath)
            // However, to keep it clean, if we resolved the path, we might just skip the data setting 
            // to avoid confusing RetroArch.
            // ... Actually, existing code might already set data. Let's strictly control it.
            
            // Check if we already have a resolved path or if strict mode allowed file:// URI
            // But if generic loop didn't set Data correctly for content:// (and didn't resolve to a file path)
            // Retry setting data for RetroArch specifically
            
            if (packageName.startsWith("com.retroarch")) {
                
                // 1. Ensure CONFIGFILE is present
                if (!intent.hasExtra("CONFIGFILE")) {
                    val configFile = "/storage/emulated/0/Android/data/$packageName/files/retroarch.cfg"
                    intent.putExtra("CONFIGFILE", configFile)
                }
                
                // 2. Ensure ROM uses resolved path if available
                if (resolvedRomPath != null) {
                    intent.putExtra("ROM", resolvedRomPath)
                }
 
                if (extras != null) {
                    for (extra in extras) {
                         val key = extra["key"] as? String
                         val value = extra["value"]
                         if (key == "ROM" && value != null) {
                             val valStr = value.toString()
                             if (valStr.startsWith("content://")) {
                                 val uri = Uri.parse(valStr)
                                 
                                 // Grant permissions (Read/Write) - We focus on ROM extra and ClipData
                                 
                                 // Grant permissions (Read/Write)
                                 intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                 intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                                 intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                 
                                 // CRITICAL for Android 10+: Set ClipData to ensure permission propagation
                                 intent.clipData = android.content.ClipData.newRawUri("ROM", uri)
                             }
                         }
                    }
                }
            }
            
            if (intent.resolveActivity(context.packageManager) != null) {
                // Assuming we want to block input or something similar, but that logic is in MainActivity
                // We'll just launch here
                context.startActivity(intent)
                result.success(true)
            } else {
                 result.error("LAUNCH_FAILED", "Activity not found for $packageName", null)
            }
        } catch (e: Exception) {
             e.printStackTrace()
             result.error("LAUNCH_FAILED", e.message, e.toString())
        }
    }
 
    private fun cleanUri(uri: String): String {
        var result = uri
        
        // Handle wrapped SAF URIs (common when passing between Flutter and Native via Uri.file)
        if (result.contains("content%3A//", ignoreCase = true)) {
            val index = result.lowercase().indexOf("content%3a//")
            // Unwrap and fix scheme separator
            result = "content://" + result.substring(index + 12)
        } else if (result.startsWith("file:///content://", ignoreCase = true)) {
            // Simple unwrap
            result = result.substring(8)
        }
        
        // Fix double encoding: some layers (like Dart's Uri.file) encode % as %25.
        if (result.startsWith("content://") && result.contains("%25")) {
            result = Uri.decode(result)
        }
        
        return result
    }
 
    private fun resolveSafUriToPath(context: Context, uri: Uri): String? {
        try {
            // Check if it's an ExternalStorageProvider URI
            if (isExternalStorageDocument(uri)) {
                var docId = android.provider.DocumentsContract.getDocumentId(uri)
                
                // Decode if needed (some IDs come with %3A instead of :)
                if (docId.contains("%3A") || docId.contains("%3a")) {
                    docId = Uri.decode(docId)
                }

                val split = docId.split(":").toTypedArray()
                if (split.size < 2) {
                     println("resolveSafUriToPath: Invalid docId format (missing colon): $docId")
                     return null
                }
                
                val type = split[0]
                val path = split[1]
                
                if ("primary".equals(type, ignoreCase = true)) {
                    // Internal Storage
                    return Environment.getExternalStorageDirectory().toString() + "/" + path
                } else {
                    // SD Card: /storage/UUID/...
                    return "/storage/" + type + "/" + path
                }
            }
        } catch (e: Exception) {
            println("Error resolving URI to path: $e")
        }
        return null
    }

    private fun getDefaultLibretroDirectory(retroArchPackage: String): String {
        return "/data/user/0/$retroArchPackage/cores/"
    }

    private fun isExternalStorageDocument(uri: Uri): Boolean {
        return "com.android.externalstorage.documents" == uri.authority
    }
}
