bl_info = {
    "name": "Fluorescent Sync",
    "author": "Fluorescent Team",
    "version": (1, 0),
    "blender": (3, 0, 0),
    "location": "View3D > Sidebar > Fluorescent",
    "description": "Live syncs Blender scene changes to the Fluorescent engine via WebSockets.",
    "warning": "This is a stub implementation.",
    "category": "3D View",
}

import bpy

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
        row.label(text="Sync Status: Disconnected")

        row = layout.row()
        row.operator("fluorescent.connect")

class FluorescentConnectOperator(bpy.types.Operator):
    """Connect to Fluorescent Engine"""
    bl_idname = "fluorescent.connect"
    bl_label = "Connect to Engine"

    def execute(self, context):
        self.report({'INFO'}, "Stub: Would connect via WebSocket here.")
        return {'FINISHED'}

def register():
    bpy.utils.register_class(FluorescentSyncPanel)
    bpy.utils.register_class(FluorescentConnectOperator)

def unregister():
    bpy.utils.unregister_class(FluorescentSyncPanel)
    bpy.utils.unregister_class(FluorescentConnectOperator)

if __name__ == "__main__":
    register()
