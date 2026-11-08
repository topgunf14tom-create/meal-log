package __PACKAGE__

// ヘルスコネクトの権限画面から「プライバシーポリシー」として開かれる説明画面。
// tool/setup.sh（setup.ps1）が android/ にコピーする。

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = TextView(this).apply {
            setPadding(48, 48, 48, 48)
            textSize = 16f
            text = """
                食事記録アプリのヘルスケアデータの使い方

                ・ヘルスコネクトから体重・体脂肪率・除脂肪量・身長・歩数・エクササイズ・活動カロリーを読み取ります
                ・読み取ったデータは、体重記録と1日の消費カロリーの計算に使い、この端末の中だけに保存します
                ・ヘルスコネクトへの書き込みや、外部への送信はしません
                ・権限はヘルスコネクトの設定からいつでも取り消せます
            """.trimIndent()
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
