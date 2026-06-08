#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera los audios de voz NEURONAL (gratis, Microsoft edge-tts) para la app.
Se ejecuta UNA VEZ en la PC; la tablet solo reproduce los .mp3 (offline).

Uso:
    pip install edge-tts
    python tools/generate_voice.py

Cada audio se guarda como  app/assets/audio/<hash>.mp3
donde  hash = sha1("<area>|<texto>")[:16]   ← el MISMO cálculo en Dart,
para que la app encuentre el clip por (área, texto) sin un manifiesto.
"""
import asyncio
import hashlib
import os
import edge_tts

AUDIO_DIR = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "audio")

# Voz mexicana (Dalia) para ambas áreas; tono distinto por área.
VOZ = "es-MX-DaliaNeural"
PROSODIA = {
    "pediatria":   {"rate": "+4%",  "pitch": "+0Hz"},   # animada y cálida
    "ginecologia": {"rate": "-3%",  "pitch": "+0Hz"},   # calmada y cercana
}

# --- Frases de interfaz (DEBEN coincidir EXACTO con voice_service.dart) ---
UI = {
    "pediatria": {
        "welcome": "Antes de irse, ¿nos regala treinta segundos? Su opinión nos ayuda a cuidar mejor a cada niña y niño que atendemos. Es totalmente anónima. Toque comenzar cuando guste.",
        "thanks":  "¡Gracias por su tiempo! Su opinión nos ayuda a brindar la mejor atención a cada niña y niño. Le deseamos una pronta recuperación a su pequeño.",
    },
    "ginecologia": {
        "welcome": "Antes de irte, ¿nos regalas treinta segundos? Tu opinión nos ayuda a mejorar la atención para cada mamá y bebé. Es totalmente anónima. Toca comenzar cuando quieras.",
        "thanks":  "¡Gracias mamá! Tu voz nos ayuda a brindar una mejor experiencia a cada familia. Te deseamos lo mejor a ti y a tu bebé.",
    },
}

# --- Preguntas (idénticas a models.dart kPreguntasSeed) ---
PREGUNTAS = {
    "pediatria": [
        "¿Considera que el motivo de atención de su paciente fue atendido adecuadamente?",
        "¿El personal médico resolvió sus dudas de manera clara?",
        "¿La atención y calidez del equipo de enfermería fue el adecuado?",
        "¿Cómo califica la comodidad de las instalaciones?",
    ],
    "ginecologia": [
        "¿Te sentiste acompañada y bien atendida durante tu estancia y recuperación?",
        "¿El personal médico resolvió tus dudas sobre tus cuidados y los de tu bebé?",
        "¿La atención y calidez del equipo de enfermería fue el adecuado?",
        "¿Consideras que tus necesidades y las de tu bebé fueron atendidas adecuadamente?",
        "¿Cómo califica la comodidad de las instalaciones?",
    ],
}


def clave(area: str, texto: str) -> str:
    return hashlib.sha1(f"{area}|{texto}".encode("utf-8")).hexdigest()[:16]


async def generar(area: str, texto: str):
    os.makedirs(AUDIO_DIR, exist_ok=True)
    destino = os.path.join(AUDIO_DIR, f"{clave(area, texto)}.mp3")
    if os.path.exists(destino):
        print(f"  (existe) {os.path.basename(destino)}")
        return
    p = PROSODIA[area]
    tts = edge_tts.Communicate(texto, VOZ, rate=p["rate"], pitch=p["pitch"])
    await tts.save(destino)
    print(f"  ✓ {os.path.basename(destino)}  «{texto[:48]}…»")


async def main():
    total = 0
    for area in ("pediatria", "ginecologia"):
        print(f"[{area}]")
        for texto in (UI[area]["welcome"], UI[area]["thanks"]):
            await generar(area, texto); total += 1
        for texto in PREGUNTAS[area]:
            await generar(area, texto); total += 1
    print(f"\nListo: {total} clips en {os.path.abspath(AUDIO_DIR)}")


if __name__ == "__main__":
    asyncio.run(main())
