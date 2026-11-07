plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.repro"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
        targetSdk = 36
    }
    lint {
        checkOnly += "DataExtractionRules"
        warningsAsErrors = true
    }
}
