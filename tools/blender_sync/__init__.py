bl_info = {
    "name": "Fluorescent Sync",
    "author": "Fluorescent Team",
    "version": (1, 1),
    "blender": (3, 0, 0),
    "location": "View3D > Sidebar > Fluorescent",
    "description": "Live syncs Blender scene changes to the Fluorescent engine via WebSockets.",
    "warning": "Ensure the websocket server is running.",
    "category": "3D View",
}

import bpy
import json
import urllib.request
import threading
import time

class FluorescentSyncState:
    is_connected = False
    server_url = "http://localhost:8080/sync"

state = FluorescentSyncState()

def send_update(data):
    if not state.is_connected:
        return
    try:
        req = urllib.request.Request(state.server_url)
        req.add_header('Content-Type', 'application/json; charset=utf-8')
        jsondata = json.dumps(data)
        jsondataasbytes = jsondata.encode('utf-8')
        req.add_header('Content-Length', len(jsondataasbytes))
        urllib.request.urlopen(req, jsondataasbytes, timeout=1)
    except Exception as e:
        print(f"Fluorescent Sync Error: {e}")
        state.is_connected = False

def on_depsgraph_update(scene, depsgraph):
    if not state.is_connected:
        return

    updates = []
    for update in depsgraph.updates:
        if update.id.bl_rna.identifier == 'Object':
            obj = update.id
            updates.append({
                "type": "object_update",
                "name": obj.name,
                "location": list(obj.location),
                "rotation": list(obj.rotation_euler),
                "scale": list(obj.scale)
            })

    if updates:
        send_update({"updates": updates})

class FluorescentSyncPanel(bpy.types.Panel):
    """Creates a Panel in the scene context of the properties editor"""
    bl_label = "Fluorescent Live Sync"
    bl_idname = "SCENE_PT_fluorescent_sync"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'Fluorescent'

    def draw(self, context):
        layout = self.layout
        row = layout.row()

        status = "Connected" if state.is_connected else "Disconnected"
        row.label(text=f"Sync Status: {status}")

        row = layout.row()
        if state.is_connected:
            row.operator("fluorescent.disconnect", text="Disconnect")
        else:
            row.operator("fluorescent.connect", text="Connect to Engine")

class FluorescentConnectOperator(bpy.types.Operator):
    """Connect to Fluorescent Engine"""
    bl_idname = "fluorescent.connect"
    bl_label = "Connect"

    def execute(self, context):
        state.is_connected = True
        self.report({'INFO'}, f"Connected to {state.server_url}")
        return {'FINISHED'}

class FluorescentDisconnectOperator(bpy.types.Operator):
    """Disconnect from Fluorescent Engine"""
    bl_idname = "fluorescent.disconnect"
    bl_label = "Disconnect"

    def execute(self, context):
        state.is_connected = False
        self.report({'INFO'}, "Disconnected")
        return {'FINISHED'}

def register():
    bpy.utils.register_class(FluorescentSyncPanel)
    bpy.utils.register_class(FluorescentConnectOperator)
    bpy.utils.register_class(FluorescentDisconnectOperator)
    bpy.app.handlers.depsgraph_update_post.append(on_depsgraph_update)

def unregister():
    bpy.utils.unregister_class(FluorescentSyncPanel)
    bpy.utils.unregister_class(FluorescentConnectOperator)
    bpy.utils.unregister_class(FluorescentDisconnectOperator)
    if on_depsgraph_update in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.remove(on_depsgraph_update)

if __name__ == "__main__":
    register()
