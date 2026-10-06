// Patches flanne.TimeToLive in Assembly-CSharp.dll so that pooled effects expire without
// MonoBehaviour.Invoke / CancelInvoke.
//
// The original OnEnable calls Invoke("Deactivate", lifetime) and OnDisable calls CancelInvoke().
// Unity's CancelInvoke walks every pending delayed call (Invokes and waiting coroutines of all
// objects), and the game pools thousands of these objects (bullet impacts, damage numbers, death
// effects), each enabled and disabled once when a run loads and again whenever one expires early.
// On the PC this was about half of the map load; under box64 on a handheld it is minutes.
//
// After the patch: a private, non serialized float portDeadline; OnEnable and Refresh set it to
// Time.time + lifetime; a new Update calls the original Deactivate() once Time.time reaches it
// (Time.time stops while the game is paused, as Invoke does); OnDisable is removed.
//
// Build: mcs -r:Mono.Cecil.dll -out:ttl_patch.exe ttl_patch.cs
// Usage: mono ttl_patch.exe <Managed dir> <output Assembly-CSharp.dll>
using System;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class TtlPatch
{
    static int Main(string[] args)
    {
        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(args[0]);
        var asm = AssemblyDefinition.ReadAssembly(System.IO.Path.Combine(args[0], "Assembly-CSharp.dll"),
            new ReaderParameters { AssemblyResolver = resolver });
        var mod = asm.MainModule;
        var ttl = mod.GetType("flanne.TimeToLive");
        if (ttl == null || ttl.Fields.Any(f => f.Name == "portDeadline")) {
            Console.Error.WriteLine("flanne.TimeToLive missing or already patched");
            return 1;
        }
        var lifetime = ttl.Fields.Single(f => f.Name == "lifetime");
        var deactivate = ttl.Methods.Single(m => m.Name == "Deactivate");
        var onEnable = ttl.Methods.Single(m => m.Name == "OnEnable");
        var refresh = ttl.Methods.Single(m => m.Name == "Refresh");
        var onDisable = ttl.Methods.Single(m => m.Name == "OnDisable");

        var core = resolver.Resolve(mod.AssemblyReferences.Single(r => r.Name == "UnityEngine.CoreModule"));
        var timeType = core.MainModule.GetType("UnityEngine.Time");
        var getTime = mod.ImportReference(timeType.Methods.Single(m => m.Name == "get_time"));

        var deadline = new FieldDefinition("portDeadline", FieldAttributes.Private, mod.TypeSystem.Single);
        ttl.Fields.Add(deadline);

        // OnEnable / Refresh: portDeadline = Time.time + lifetime;
        foreach (var m in new[] { onEnable, refresh }) {
            m.Body.Instructions.Clear();
            m.Body.ExceptionHandlers.Clear();
            m.Body.Variables.Clear();
            var il = m.Body.GetILProcessor();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, getTime);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, lifetime);
            il.Emit(OpCodes.Add);
            il.Emit(OpCodes.Stfld, deadline);
            il.Emit(OpCodes.Ret);
        }

        // Update: if (Time.time >= portDeadline) { portDeadline = float.MaxValue; Deactivate(); }
        var update = new MethodDefinition("Update", MethodAttributes.Private | MethodAttributes.HideBySig,
            mod.TypeSystem.Void);
        {
            var il = update.Body.GetILProcessor();
            var ret = il.Create(OpCodes.Ret);
            il.Emit(OpCodes.Call, getTime);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, deadline);
            il.Emit(OpCodes.Blt_Un, ret);          // time < deadline (or NaN): nothing to do
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldc_R4, float.MaxValue);
            il.Emit(OpCodes.Stfld, deadline);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, deactivate);
            il.Append(ret);
        }
        ttl.Methods.Add(update);
        ttl.Methods.Remove(onDisable);

        asm.Write(args[1]);
        Console.WriteLine("patched flanne.TimeToLive");
        return 0;
    }
}
