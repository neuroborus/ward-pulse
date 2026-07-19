package app.wardpulse.wear.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme

private val WardPulseColorScheme = ColorScheme(
    primary = Color(0xFF67E8D4),
    primaryDim = Color(0xFF49CBBB),
    primaryContainer = Color(0xFF155B45),
    onPrimary = Color(0xFF002F2A),
    onPrimaryContainer = Color(0xFFF4FBF8),
    secondary = Color(0xFFADCEBC),
    secondaryDim = Color(0xFF91B2A1),
    secondaryContainer = Color(0xFF314F41),
    onSecondary = Color(0xFF183629),
    onSecondaryContainer = Color(0xFFD4F2E0),
    tertiary = Color(0xFFE6C349),
    tertiaryDim = Color(0xFFC9A72E),
    tertiaryContainer = Color(0xFF574500),
    onTertiary = Color(0xFF3C2F00),
    onTertiaryContainer = Color(0xFFFFE17A),
    surfaceContainerLow = Color(0xFF181D1A),
    surfaceContainer = Color(0xFF1C211E),
    surfaceContainerHigh = Color(0xFF262B28),
    onSurface = Color(0xFFE0E4DF),
    onSurfaceVariant = Color(0xFFBEC9C1),
    outline = Color(0xFF88938C),
    outlineVariant = Color(0xFF3F4943),
    background = Color.Black,
    onBackground = Color(0xFFF4FBF8),
    error = Color(0xFFFFB4AB),
    errorDim = Color(0xFFE38F88),
    errorContainer = Color(0xFF93000A),
    onError = Color(0xFF400002),
    onErrorContainer = Color(0xFFFFDAD6),
)

internal val WardPulseSuccess = Color(0xFF65D78A)

@Composable
fun WardPulseTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = WardPulseColorScheme,
        content = content,
    )
}
