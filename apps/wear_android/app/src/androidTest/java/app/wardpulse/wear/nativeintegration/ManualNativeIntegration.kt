package app.wardpulse.wear.nativeintegration

/** Real manager/data effects require the stock runner, explicit selection and device guards. */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
annotation class ManualNativeIntegration
