package app.wardpulse.wear.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme

/**
 * Wear shell theme: gray-olive chrome; provider greens/oranges/teals stay on
 * rings only (`docs/DESIGN_ASSETS.md`, `WATCH_RING_DESIGN.md`).
 */
private val WardPulseColorScheme = ColorScheme(
    primary = Color(0xFFA7B09E),
    primaryDim = Color(0xFF8A9282),
    primaryContainer = Color(0xFF3A4038),
    onPrimary = Color(0xFF1A1F1A),
    onPrimaryContainer = Color(0xFFF4FBF8),
    secondary = Color(0xFFADCEBC),
    secondaryDim = Color(0xFF91B2A1),
    secondaryContainer = Color(0xFF24332C),
    onSecondary = Color(0xFF183629),
    onSecondaryContainer = Color(0xFFD4F2E0),
    tertiary = Color(0xFFE6C349),
    tertiaryDim = Color(0xFFC9A72E),
    tertiaryContainer = Color(0xFF3D3400),
    onTertiary = Color(0xFF3C2F00),
    onTertiaryContainer = Color(0xFFFFE17A),
    surfaceContainerLow = Color(0xFF121614),
    surfaceContainer = Color(0xFF1A1F1C),
    surfaceContainerHigh = Color(0xFF323A36),
    onSurface = Color(0xFFE8EDE8),
    onSurfaceVariant = Color(0xFFA8B3AB),
    outline = Color(0xFF6F7A73),
    outlineVariant = Color(0xFF2E3632),
    background = Color(0xFF101412),
    onBackground = Color(0xFFF4FBF8),
    error = Color(0xFFFFB4AB),
    errorDim = Color(0xFFE38F88),
    errorContainer = Color(0xFF93000A),
    onError = Color(0xFF400002),
    onErrorContainer = Color(0xFFFFDAD6),
)

@Composable
fun WardPulseTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = WardPulseColorScheme,
        content = content,
    )
}
