#!/usr/bin/env python3
"""Generates NutriVision/Localizable.xcstrings (English source + Spanish).

Keys are the literal strings used in SwiftUI views, so they are picked up
automatically. Add languages by extending TRANSLATIONS and re-running.
"""
import json, pathlib

TRANSLATIONS = {
 "es": {
  "Dashboard": "Inicio", "Scan": "Escanear", "History": "Historial", "Insights": "Estadísticas",
  "Today's Meals": "Comidas de hoy", "Calorie Goal": "Meta de calorías", "Protein": "Proteína", "Carbs": "Carbohidratos",
  "Fat": "Grasa", "Water": "Agua", "Fasting": "Ayuno", "Start fast": "Iniciar ayuno", "End fast": "Terminar ayuno",
  "No meals yet": "Aún no hay comidas", "Add food": "Añadir comida", "Settings": "Ajustes", "Done": "Listo",
  "Save to Log": "Guardar en el registro", "Update Meal": "Actualizar comida", "Serving size": "Tamaño de porción",
  "kcal total": "kcal en total", "Breakfast": "Desayuno", "Lunch": "Almuerzo", "Dinner": "Cena", "Snack": "Merienda",
  "Search foods": "Buscar alimentos", "Add Food": "Añadir alimento", "Favorites": "Favoritos", "Recent": "Recientes",
  "My Foods & Recipes": "Mis alimentos y recetas", "Database": "Base de datos", "Your Foods": "Tus alimentos",
  "No results": "Sin resultados", "Close": "Cerrar", "Cancel": "Cancelar", "Save": "Guardar", "Delete": "Eliminar",
  "Edit": "Editar", "Undo": "Deshacer", "Meal deleted": "Comida eliminada", "Search meals": "Buscar comidas",
  "No Meals Logged": "Sin comidas registradas", "Week": "Semana", "Month": "Mes", "Calories": "Calorías",
  "Macros": "Macros", "Weight": "Peso", "Weight & water": "Peso y agua", "Log Weight": "Registrar peso",
  "Weigh-ins": "Pesajes", "Adaptive goal": "Meta adaptable", "Water today": "Agua de hoy",
  "Welcome to NutriVision": "Bienvenido a NutriVision", "About you": "Sobre ti", "How active are you?": "¿Qué tan activo eres?",
  "Your goal": "Tu meta", "Your daily targets": "Tus metas diarias", "Continue": "Continuar", "Back": "Atrás",
  "Get Started": "Empezar", "Profile": "Perfil", "Goals": "Metas", "Units": "Unidades", "Metric": "Métrico", "Imperial": "Imperial",
  "Meal reminders": "Recordatorios de comidas", "Integrations": "Integraciones", "Sync with Apple Health": "Sincronizar con Apple Salud",
  "iCloud sync": "Sincronización con iCloud", "Export": "Exportar", "About": "Acerca de", "Name": "Nombre", "Age": "Edad",
  "Height": "Estatura", "Activity": "Actividad", "Goal": "Meta", "Diet style": "Tipo de dieta", "Balanced": "Equilibrada",
  "High protein": "Alta en proteína", "Low carb": "Baja en carbohidratos", "Keto": "Keto", "Sedentary": "Sedentario",
  "Lose weight": "Perder peso", "Maintain weight": "Mantener peso", "Gain weight": "Ganar peso",
  "Camera access needed": "Se necesita acceso a la cámara", "Open Settings": "Abrir Ajustes",
  "Choose a photo instead": "Elegir una foto", "Choose a Photo": "Elegir una foto", "Retake": "Repetir",
  "Point your camera at food or a barcode": "Apunta la cámara a un alimento o código de barras",
  "Analyzing…": "Analizando…", "Label": "Etiqueta", "PORTION": "PORCIÓN", "DETECTED": "DETECTADO", "PRODUCT": "PRODUCTO",
  "AI ESTIMATE": "ESTIMACIÓN IA", "NOT QUITE? TRY": "¿NO ES? PRUEBA", "Time": "Hora", "Enter manually": "Introducir manualmente",
  "Create food or recipe": "Crear alimento o receta", "New Food": "Nuevo alimento", "New Recipe": "Nueva receta",
  "Ingredients": "Ingredientes", "Add ingredient": "Añadir ingrediente", "Servings": "Porciones", "Per serving": "Por porción",
  "Streak": "Racha", "day streak": "días seguidos", "best streak": "mejor racha", "consistency": "constancia",
 },
}

catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
for key in sorted({k for lang in TRANSLATIONS.values() for k in lang}):
    localizations = {}
    for lang, table in TRANSLATIONS.items():
        if key in table:
            localizations[lang] = {"stringUnit": {"state": "translated", "value": table[key]}}
    catalog["strings"][key] = {"extractionState": "manual", "localizations": localizations}

path = pathlib.Path(__file__).resolve().parent.parent / "NutriVision" / "Localizable.xcstrings"
path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False))
print(f"wrote {len(catalog['strings'])} strings")
