#!/usr/bin/env python3
"""
Dynamic Island (Notch Island 3.0) MCP Server
Serveur MCP optimisé (JSON-RPC 2.0 Stdio) offrant un contrôle direct
de la Dynamic Island macOS native :
  - Statut en temps réel (PID, RAM, calibrage 179x32mm, Liquid Glass 3D, batterie)
  - Salle d'attente de fichiers (Shelf) : listing, récupération du dernier fichier déposé, ajout, nettoyage
  - Captures d'écran interactives et collage direct du presse-papier
  - Contrôle Apple Music natif via l'îlot
  - HUD dynamique Apple et notifications style iOS/macOS
  - Gestion du son haptique
"""

from __future__ import annotations

import sys
import os
import json
import subprocess
import glob
import time
import shutil
from datetime import datetime
from pathlib import Path

CACHE_SCREENSHOTS_DIR = os.path.expanduser("~/Library/Caches/NotchIslandScreenshots")

def post_notification(name: str, user_info: dict | None = None) -> bool:
    """Poste une notification système via NSDistributedNotificationCenter."""
    info = user_info or {}
    try:
        import Cocoa
        center = Cocoa.NSDistributedNotificationCenter.defaultCenter()
        center.postNotificationName_object_userInfo_deliverImmediately_(
            name, None, info, True
        )
        return True
    except Exception:
        cmd = [
            "python3", "-c",
            f"import Cocoa; Cocoa.NSDistributedNotificationCenter.defaultCenter().postNotificationName_object_userInfo_deliverImmediately_('{name}', None, {json.dumps(info)}, True)"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return res.returncode == 0

# --------------------------------------------------------------------------- #
# Handlers des Outils
# --------------------------------------------------------------------------- #

def tool_status(args: dict) -> dict:
    """Statut d'activité, PID, RAM et métriques de la Dynamic Island."""
    try:
        pid_res = subprocess.run(
            ["pgrep", "-f", "NotchIsland.app/Contents/MacOS/NotchIsland"],
            capture_output=True, text=True
        )
        pid = pid_res.stdout.strip()
        if not pid:
            pid_res2 = subprocess.run(["pgrep", "-f", "NotchIsland"], capture_output=True, text=True)
            pids = pid_res2.stdout.strip().split()
            pid = pids[0] if pids else None
        
        active = bool(pid)
        mem = "0 MB"
        if active:
            mem_res = subprocess.run(
                ["ps", "-o", "rss=", "-p", pid],
                capture_output=True, text=True
            )
            rss = mem_res.stdout.strip()
            if rss and rss.isdigit():
                mem = f"{int(rss) / 1024:.1f} Mo"

        files_count = len([f for f in os.listdir(CACHE_SCREENSHOTS_DIR) if not f.startswith(".")]) if os.path.exists(CACHE_SCREENSHOTS_DIR) else 0

        batt_str = "Secteur"
        try:
            pm = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True)
            for line in pm.stdout.splitlines():
                if "%" in line:
                    batt_str = line.strip()
                    break
        except Exception:
            pass

        return {
            "active": active,
            "pid": int(pid) if active and pid and pid.isdigit() else pid,
            "memory_ram": mem,
            "notch_calibration": "179px × 32px (Zéro débordement)",
            "material": "Liquid Glass 3D (Dégradé noir pur -> verre translucide)",
            "shelf_items_count": files_count,
            "shelf_directory": CACHE_SCREENSHOTS_DIR,
            "battery_system_state": batt_str
        }
    except Exception as e:
        return {"error": str(e), "active": False}

def tool_get_shelf_files(args: dict) -> dict:
    """Liste tous les fichiers présents dans la salle d'attente de la Dynamic Island."""
    limit = args.get("limit", 20)
    if not os.path.exists(CACHE_SCREENSHOTS_DIR):
        return {"files": [], "total": 0, "shelf_dir": CACHE_SCREENSHOTS_DIR}
    
    entries = []
    for f in os.listdir(CACHE_SCREENSHOTS_DIR):
        full_path = os.path.join(CACHE_SCREENSHOTS_DIR, f)
        if os.path.isfile(full_path) and not f.startswith("."):
            st = os.stat(full_path)
            entries.append({
                "name": f,
                "path": full_path,
                "size_bytes": st.st_size,
                "size_human": f"{st.st_size / 1024:.1f} Ko" if st.st_size < 1024*1024 else f"{st.st_size / (1024*1024):.2f} Mo",
                "modified_iso": datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                "modified_timestamp": st.st_mtime,
                "is_image": f.lower().endswith((".png", ".jpg", ".jpeg", ".tiff", ".webp", ".gif"))
            })
    
    entries.sort(key=lambda x: x["modified_timestamp"], reverse=True)
    return {
        "files": entries[:limit],
        "total": len(entries),
        "shelf_dir": CACHE_SCREENSHOTS_DIR
    }

def tool_get_latest_drop(args: dict) -> dict:
    """Récupère directement le dernier fichier ou capture déposé dans la Dynamic Island."""
    res = tool_get_shelf_files({"limit": 1})
    files = res.get("files", [])
    if not files:
        return {"found": False, "message": "Aucun fichier déposé dans la Dynamic Island actuellement."}
    latest = files[0]
    return {
        "found": True,
        "name": latest["name"],
        "path": latest["path"],
        "size_bytes": latest["size_bytes"],
        "size_human": latest["size_human"],
        "modified_iso": latest["modified_iso"],
        "is_image": latest["is_image"]
    }

def tool_add_file_to_shelf(args: dict) -> dict:
    """Copie un fichier depuis le système de fichiers vers la salle d'attente de l'île."""
    source_path = os.path.abspath(os.path.expanduser(args.get("source_path", "")))
    if not os.path.exists(source_path):
        return {"ok": False, "error": f"Fichier source introuvable : {source_path}"}
    
    os.makedirs(CACHE_SCREENSHOTS_DIR, exist_ok=True)
    filename = os.path.basename(source_path)
    dest_path = os.path.join(CACHE_SCREENSHOTS_DIR, filename)
    shutil.copy2(source_path, dest_path)
    
    post_notification("com.antigravity.notchisland.paste")
    return {
        "ok": True,
        "staged_path": dest_path,
        "filename": filename,
        "size_bytes": os.path.getsize(dest_path)
    }

def tool_clear_shelf(args: dict) -> dict:
    """Supprime ou vide les éléments de la salle d'attente."""
    if not os.path.exists(CACHE_SCREENSHOTS_DIR):
        return {"cleared_count": 0}
    
    deleted = 0
    for f in os.listdir(CACHE_SCREENSHOTS_DIR):
        fp = os.path.join(CACHE_SCREENSHOTS_DIR, f)
        if os.path.isfile(fp) and not f.startswith("."):
            try:
                os.remove(fp)
                deleted += 1
            except Exception:
                pass
    
    return {"ok": True, "cleared_count": deleted}

def tool_trigger_screenshot(args: dict) -> dict:
    """Déclenche la capture d'écran interactive macOS qui se loge dans l'île."""
    ok = post_notification("com.antigravity.notchisland.screenshot")
    return {"ok": ok, "action": "interactive_screenshot_triggered"}

def tool_paste_clipboard(args: dict) -> dict:
    """Colle l'image ou le fichier du presse-papier dans la Dynamic Island."""
    ok = post_notification("com.antigravity.notchisland.paste")
    return {"ok": ok, "action": "paste_clipboard_into_shelf"}

def tool_music_control(args: dict) -> dict:
    """Contrôle la lecture musicale (play, pause, toggle, next, prev) via l'île."""
    action = args.get("action", "toggle")
    ok = post_notification("com.antigravity.notchisland.musicControl", {"action": action})
    return {"ok": ok, "action": action}

def tool_select_tab(args: dict) -> dict:
    """Bascule l'onglet affiché (music ou shelf)."""
    tab = args.get("tab", "shelf")
    ok = post_notification("com.antigravity.notchisland.selectTab", {"tab": tab})
    return {"ok": ok, "selected_tab": tab}

def tool_test_charge(args: dict) -> dict:
    """Déclenche l'animation du HUD de chargeur intelligent (Watts & batterie)."""
    watts = args.get("watts", 96)
    battery = args.get("battery", 85)
    ok = post_notification("com.antigravity.notchisland.testCharge", {"watts": int(watts), "battery": int(battery)})
    return {"ok": ok, "watts": watts, "battery": battery}

def tool_set_sound(args: dict) -> dict:
    """Active ou désactive les signaux sonores haptiques de l'île (Tink/Pop)."""
    enabled = args.get("enabled", True)
    ok = post_notification("com.antigravity.notchisland.setSound", {"enabled": bool(enabled)})
    return {"ok": ok, "sound_enabled": enabled}

def tool_notify(args: dict) -> dict:
    """Déclenche une notification dynamique style Apple avec expansion visuelle sous l'encoche et bannière native macOS."""
    title = args.get("title", "Antigravity")
    message = args.get("message", "Notification")
    icon = args.get("icon", "sparkles")
    tint = args.get("tint", "cyan")
    duration = args.get("duration", 6)
    
    # 1. Message direct dans la Dynamic Island physique sous l'encoche
    post_notification("com.antigravity.notchisland.showMessage", {
        "title": title,
        "body": message,
        "icon": icon,
        "tint": tint,
        "duration": duration
    })
    
    # 2. Bannière native Apple macOS
    sound = args.get("sound", "Glass")
    apple_script = f'''
    display notification "{message}" with title "{title}" subtitle "Dynamic Island" sound name "{sound}"
    '''
    subprocess.run(["osascript", "-e", apple_script], capture_output=True, text=True)
    
    return {
        "ok": True,
        "title": title,
        "message": message,
        "island_rendered": True,
        "style": "apple_liquid_glass"
    }

# --------------------------------------------------------------------------- #
# Spécifications des Outils MCP
# --------------------------------------------------------------------------- #

TOOLS = [
    {
        "name": "notch_island_status",
        "description": "Retourne le statut en temps réel de la Dynamic Island (Notch Island 3.0) : état actif, PID, consommation RAM, calibrage encoche (179x32mm), et nombre d'éléments dans la salle d'attente.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "notch_island_notify",
        "description": "Déclenche une notification dynamique haut de gamme style Apple : expansion visuelle sous l'encoche de l'écran avec halo, carillon audio et bannière native macOS.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Titre principal de la notification (ex: 'Dynamic Island')"
                },
                "message": {
                    "type": "string",
                    "description": "Contenu du message notifié"
                },
                "sound": {
                    "type": "string",
                    "description": "Nom du son macOS (ex: 'Glass', 'Tink', 'Ping')"
                }
            },
            "required": ["message"]
        }
    },
    {
        "name": "notch_island_get_shelf_files",
        "description": "Liste les fichiers et captures d'écran présents dans la salle d'attente (Drop Shelf) de la Dynamic Island, triés du plus récent au plus ancien.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "Nombre maximum d'éléments à retourner (défaut: 20)"
                }
            },
            "required": []
        }
    },
    {
        "name": "notch_island_get_latest_drop",
        "description": "Récupère directement le tout dernier fichier ou capture d'écran déposé dans la Dynamic Island (ex: image déposée par l'utilisateur, capture récente) avec son chemin absolu sur disque.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "notch_island_add_file_to_shelf",
        "description": "Copie et met en attente un fichier quelconque du disque dans la Dynamic Island afin qu'il apparaisse visuellement dans le shelf sous l'encoche.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source_path": {
                    "type": "string",
                    "description": "Chemin absolu ou relatif du fichier à ajouter à l'île"
                }
            },
            "required": ["source_path"]
        }
    },
    {
        "name": "notch_island_clear_shelf",
        "description": "Vide les fichiers présents dans la salle d'attente de la Dynamic Island.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "notch_island_trigger_screenshot",
        "description": "Déclenche une capture d'écran interactive macOS qui se dépose automatiquement dans la Dynamic Island.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "notch_island_paste_clipboard",
        "description": "Colle l'image ou le fichier présent dans le presse-papier macOS directement dans la Dynamic Island.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "notch_island_music_control",
        "description": "Pilote Apple Music directement depuis la Dynamic Island (play, pause, toggle, next, prev).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["play", "pause", "toggle", "next", "prev"],
                    "description": "Action de lecture à effectuer"
                }
            },
            "required": ["action"]
        }
    },
    {
        "name": "notch_island_select_tab",
        "description": "Bascule l'onglet actif de la Dynamic Island (musique ou salle d'attente / shelf).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tab": {
                    "type": "string",
                    "enum": ["music", "shelf"],
                    "description": "Onglet à afficher"
                }
            },
            "required": ["tab"]
        }
    },
    {
        "name": "notch_island_test_charge",
        "description": "Déclenche l'animation du HUD de chargeur intelligent (Watts et anneau de batterie) sous l'encoche.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "watts": {
                    "type": "integer",
                    "description": "Puissance en Watts simulée (ex: 67, 96, 140)"
                },
                "battery": {
                    "type": "integer",
                    "description": "Pourcentage de batterie (ex: 85)"
                }
            },
            "required": []
        }
    },
    {
        "name": "notch_island_set_sound",
        "description": "Active ou coupe le carillon doux (Tink / Pop) de la Dynamic Island.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "enabled": {
                    "type": "boolean",
                    "description": "True pour activer les sons, False pour le mode silencieux"
                }
            },
            "required": ["enabled"]
        }
    }
]

DISPATCH = {
    "notch_island_status": tool_status,
    "notch_island_notify": tool_notify,
    "notch_island_get_shelf_files": tool_get_shelf_files,
    "notch_island_get_latest_drop": tool_get_latest_drop,
    "notch_island_add_file_to_shelf": tool_add_file_to_shelf,
    "notch_island_clear_shelf": tool_clear_shelf,
    "notch_island_trigger_screenshot": tool_trigger_screenshot,
    "notch_island_paste_clipboard": tool_paste_clipboard,
    "notch_island_music_control": tool_music_control,
    "notch_island_select_tab": tool_select_tab,
    "notch_island_test_charge": tool_test_charge,
    "notch_island_set_sound": tool_set_sound
}

def handle_request(req: dict) -> dict:
    req_id = req.get("id")
    method = req.get("method")
    params = req.get("params", {})

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "notch-island-mcp", "version": "1.1.0"}
            }
        }
    elif method == "notifications/initialized":
        return None
    elif method == "tools/list":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}
    elif method == "tools/call":
        tool_name = params.get("name")
        tool_args = params.get("arguments", {})
        handler = DISPATCH.get(tool_name)
        if not handler:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "isError": True,
                "result": {"content": [{"type": "text", "text": f"Outil '{tool_name}' inconnu."}]}
            }
        try:
            res = handler(tool_args)
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"content": [{"type": "text", "text": json.dumps(res, ensure_ascii=False, indent=2)}]}
            }
        except Exception as e:
            import traceback
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "isError": True,
                "result": {"content": [{"type": "text", "text": f"Erreur {tool_name}: {str(e)}\n{traceback.format_exc()}"}]}
            }
    else:
        return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Method not found: {method}"}}

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = handle_request(req)
            if resp:
                sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        except Exception as e:
            err = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": str(e)}}
            sys.stdout.write(json.dumps(err) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
