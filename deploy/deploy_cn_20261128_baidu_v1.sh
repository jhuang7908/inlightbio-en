#!/usr/bin/env bash
# InLightBio CN deploy baidu_v1 - 2026-11-28
# Adds the Baidu Tongji (hm.js) snippet to the <head> of every public HTML page (94 files).
# Web-only: stages a FRESH release root = copy of the live root, then inserts the snippet before the
# first </head> of each listed file (byte-exact, verified by sha256). No downloads needed.
# Does not change nginx locations, SSL, ACME, or APIs. The only nginx edit is the existing
# one-line `root` switch used by prior CN deploys. Deletes nothing.
# Approved by Jing (via parent). CN PR #156 "接入百度统计 hm.js" merged as 24e5321.
set -euo pipefail

SITE_ID="cae45cbf88c310c773dd8a37087c2f8c"
# dest_rel|live_sha256_before|sha256_after
FILES=(
"index.html|a28dbe1f77decbc3027d8f7f09b0ec82c93a5e5063b25d3f14d40c6de0769d26|75f38cf776848f83b5f429193dc59cb155ac3dac0830298fcb5255bc9132cfd0"
"pages/article/a-invivocar.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/a-trap.html|3af72fd2d91cc09375226911c50fcf1507ab0f3c9bcd721f2d5ceef1e692adf4|673f35e10cd382b4dcb742047e6cb06541037bc088142f936001e651f753765a"
"pages/article/c1-org-1.html|ed83adfa16defd92b60ba81558bb52b5578c4881de7c2554b4a90e58a271f992|a191582b1900399d21a8bf761b2e8542dd4aa27aae9180fa14b5d88b7453fb39"
"pages/article/c1-org-2.html|f76f7273e22693da5604663a7a5199d8c0fac31240912dc3c3fe0a69c88f389a|72dba20f1dcb3e1339c2b87d3bceabd7e181d6f2df924072b4dee3580a3aa9e9"
"pages/article/c1-org-3.html|a8d74a9ac7b9304de396b1adad8b08b69c86b39d9125a92934622bad54b2e368|d69b7edb7ac30de7e26e02ee0f8598bb70c0ea825de840dee3d63cece197b3fe"
"pages/article/c1-org-4.html|f68d5b55906aa9692fbee1a72f0c7910a2eac85e498d69ceb5d7e955ed95d1fd|1249e3db5500a6910be687fb529fedecf135650cc73185a7af6e14007f03cf7f"
"pages/article/c1-org-5.html|df33067ddde86652c7d8de0ed3114fa09cc29da330fef02e4ec98c1017c72d6d|0d5087869383f867d47d640f18b12b66017d8ba9adc66b3513414e8a312a479b"
"pages/article/c2-ai-1.html|e26c2bbe1d9bdf2ce33533200c8bc83abb4840a47ec516aa97ba0a34e127e5cc|28025b6640c026bf1a5f09bcc7a104342628ec61054fc6a7fc774e129470f7b8"
"pages/article/c2-ai-2.html|1bc16d6dae4b5779de092001daf076ccec85b5152528f1b82f1a2030c8b95cda|7faffbce3d4df25297f2dee2d874b96121137a2670e1c69f757ba944a9b57f00"
"pages/article/c2-ai-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c2-ai-4.html|8fed960e76a25fc7af473dbbc6a467dd79fd05f19f6f38fa7dc16c78e2ebf6cb|ece284fb9d87b4354a535aaeeffaeaf7aa34b94392f615d1fc6d9c0de7ec9b25"
"pages/article/c2-ai-5.html|c490370ae05384e435128a1712d0c1758187da74acddf4af4a177f3dedf24d3e|53ad657a0c305c5896d8ce10e5412a9af70fe6dda3238ce1b25e9c7f6554c626"
"pages/article/c3-io-1.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c3-io-2.html|f6c57b6fc8887c7ac97dd549bcdb96df8f8d56bdcb70a656c4bc6557459bdc1a|90750c68d5f7e2d55df0277a1d0501a8d113bd34acf3eb1bf49e29b5b6836e16"
"pages/article/c3-io-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c3-io-4.html|1f3a4a19fe1bdb213ed65d30bb3bcb6d4e74e72042733e51220213574adb68bf|695ac33bc25244615d675ee61d322ab87e7068d4d6ba12a561b809ffb91b9b59"
"pages/article/c3-io-5.html|5deffaabf3fd6106fef7993936f150441303147a01681fe2a70ad650655d89ac|e942c618ca649683387a7034c61df1a80b26e0c6c64ec99ef62e0d998f74d1cc"
"pages/article/c4-ai-1.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c4-ai-2.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c4-ai-4.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c4-ai-5.html|d5cf0620c042e55eae6fc3aa5b6bb7168e6d0df8a240b68c90f7172a546be79b|19845b9a44ec94b50a2d1c8485fba2903e60fcae86de11a810481616c5664178"
"pages/article/c4-ai-6.html|359b52a34bd82b7eaab5ef068ab3d06a430457532ea01751e7002c2ad430f7d0|da3711f1f4392c0fe975a774eff811129d1e42046957f85c4f1e56f2388cbe0c"
"pages/article/c4-ai-7.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c4-ai-8.html|7eb5537d80f2f27a0a3f918dc2c0eab29e6d7c1962c9fc3e76f89f52c43c8e9d|1de3cddda347752982c9a73cf269a3ec866c0857e01202ae0594268b4d8eadf3"
"pages/article/c4-ai-9.html|b8cc8ef64eb6426b009c37c15603cf481f230edbbe2c9418fe38957b043a0b19|80c0ca5d5172cd3f3a7ed5e29e804c47d503b6ee38da5cfe8aa95e6f2b51f0ee"
"pages/article/c5-am-1.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c5-am-2.html|0d21264d28f6583221c66d93a52b3824ba2f2efb602977c902d8a72d1742a45b|aa7cb00e66e10de33485bdce6e4f82d6cf2a00234d7c4c6ab955523cbad246e7"
"pages/article/c5-am-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c5-am-5.html|67d48105e835aa3c4f485a15eb8c86dcee5d02faf7bf8aa06482529306075281|764cf82919930114254d3dbe5a76ab130c7b59ff9aa0735ca8eb555869ec7052"
"pages/article/c5-am-6.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c5-am-7.html|976b2769ddfa5277b9fe1ded363344ac67daf3c3f0067f18e1d979137c2da867|ffad649196829a603af45ae298a68a002e2a7af3c4184fd426ce7f352a972d6d"
"pages/article/c5-am-8.html|3e901d27bf647d4500e3fdbc0d6e9439772a17fb64e1c49f8a2517893d830651|6b3ba1134d3f0650e273170fc1ba0b5931062d37a9730fcc5878da07220cfe98"
"pages/article/c5-am-9.html|9ebf8ff0969e06b20f491845bce307a61cbb94e5117339cdd75afc563184009f|7f72ee1c086121ef415a527a48139a9643caa8ebb7407c8c58acbea3584c5e59"
"pages/article/c6-ab-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c6-ab-4.html|5e10fb61bb8e94de36d6871cf885a4a5754ffed8f6a702bdb2f63f6423662411|9a43cc0f498b3909e4e893c7252740f27a8325ba9526f7836a2556840ecb57de"
"pages/article/c6-ab-5.html|17f6ecf1f1f370b65fba4af671cbf94d8c056e7bf89d426a63ccaaee29a33584|2ddd639c8298a3ae295f70f7c0ea3b738bd5ed4e339a1484d127aca0c9112f03"
"pages/article/c6-ab-6.html|38a7d8ea8fe5b16f92e7a2d8bca27e079374434d0b2cc54c959057a93d0036bf|7184961d61122d7ba253766b80a2ca823f5c4b6dea61b7b56bb45787a8af5189"
"pages/article/c6-ab-7.html|8be8e64686e0314b9ac1dca5ca6f61955cb7d8a6fd8765145ee357e0ad336407|a4c20709844ccaca565a28f1ea414dcf1bf88f11d72ca933ae0b74efda1959e4"
"pages/article/c6-ab-8.html|0222c10d6c3bb868c32a8fc05855f8b3fd1ccfe8fd9c8e4872d907566da3e393|a9e312f32d272ca51c72f7c727bae951498a93d0a64e83180e2f2555a73bfe0a"
"pages/article/c6-ab-9.html|9c70254e6173dcee3bc362738402df17f565c81aecebd56f3cd0e5f7c2372cbf|713adc9beb868835112ee210c07c046c8125c922360b3e7c42884c07e296d048"
"pages/article/c7-cell-1.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c7-cell-2.html|2b8438a1c530a0682e17991aba9476907477532fafa52a71f4ecfdf43d4857c7|61a1ff1a8922f71b36ba5896ef63f07c0225fff6398aa3b1edce7a215a7bab61"
"pages/article/c7-cell-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c7-cell-4.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c7-cell-5.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c8-vac-1.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c8-vac-2.html|1192e7544b872a31ce09a3731cd64b78fec9309669fec62e9993c2dfb94ec8b5|b4553c0a03655ba999aaf0390fb63922c8ad849abb1a6a5ec460755edd4d67db"
"pages/article/c8-vac-3.html|77dd42f7eccb83a568726c917fac7157bba86fbbefa97b83e20ecd9892aa2d8d|0fb04c27799bb1740b3d0aa99c3e9a49b619d9b7b6ad738dc819ad00f28929f5"
"pages/article/c8-vac-4.html|4cd953652b713ac17580547469316e4a4be6361cd8e8050c2420b854726725e6|896062e7d2dc9685c281b8c45c18c6a6588a7be78f5fec0a341adcfba17e5b84"
"pages/article/c8-vac-5.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c9-rna-10.html|1d411ae42756c7277d4e6a93caf6125e9ee75569bf8ba522d991d6ef86f5864a|a033f2e412ae405f205705bff78d593038d1026edf1c4f87b72b711ca138658c"
"pages/article/c9-rna-2.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c9-rna-3.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c9-rna-5.html|2bc1f2f8d21ab82d465d9b185d4861ff05a904c3713a1106eb3c9f33cf30adab|fac36468008750556d9da8eda943df9697c8f9c5692d13d13b29e8edbcc26072"
"pages/article/c9-rna-6.html|73c46d2bcc05dacbb7f7b030bd70fa50afd23f989b368e436671902f976a7387|888294a2871b0a4ccd95ecec490bdf6f3cbb89afee7bc1d00393f6a7bd6af0a2"
"pages/article/c9-rna-7.html|b7666233c6a2736a11a9c85d938b0462dab773e3be3d9a081664b4c5583ab58f|5b1dc4a6567917b8132809403fbff4a61a6df8bb617060de50f74c0ff87595fd"
"pages/article/c9-rna-8.html|5fbd761504035040a18a3f9f340d1548d4ae30239eb5b86d6b3acfe271fe2735|b628b7a8b0813f919ad485b53e87c7fcecf618be2c91ad3bcbf19fdce85373de"
"pages/article/c9-rna-9.html|aeaee9aeaa5e879dee8494dc22c4996e5f91467e15d4bdf143cffc2e0fb7072a|2578cee491890bc704ee7efb0d56193da9a3b07e501aaf0634cf6f889d5dcb6f"
"pages/article/deals-weekly-20261128.html|d5cf7b1c3cf1c26b8ae88c920ac7813d77d1264f0ce60060cfecb836a50a1d69|67db0658ba55c0ee6120fd37494132d96ce19b8c9e89d2b1ada16046f44826ce"
"pages/article/ivonescimab-fda-crl.html|21521bea111321a50685a958bc07e0a2d2c843a582ca1f614fc3ac2d58a02525|ab27d0652bb1f45bd214fdfeb93add7fe674513801be4d08ce5cf4ca3bad50b1"
"pages/article/pfizer-starna-invivo-cart.html|2b50e0544c80685321c06036e0eb8baffd1150eecae769b82c493993b5dfb672|a93ce294440565827d91bc5d698b123f22bdf2051253c1ab1484ec56d3d8bbbf"
"pages/article/us-coins-biotech-outbound-rule.html|02b6d6c87ab4b47d3176b36ed888041932a69aaaaf65b4671caaae7deb606078|807b74fcb8186603b16133175aea9ba2d679aff31fdcbb124be449b2fefd66f5"
"pages/article/w-20261013-ba52ceae64.html|ddb5450c5344239e2e9da29297e58188455cb83400f3920dcc7c6367b6c5ac71|200d8f0967343782d3510859ccab3910fe75d5c3cd7ab751dceae71a530595df"
"pages/article/w-20261017-1ac6d48454.html|912ce0295a8ef5b72c0a1fabd5aa645e00f28f0abd152b962ca718c86e6537c0|8d40544797a07b8782e962a8ac4b901183fec67fdb4ce2edba8c9fe78e94f96c"
"pages/article/w-20261020-71c84a91b0.html|d6272a89ab25955a409d145752c6633763a8bc2f2d9808d6994f116c830fb422|c2752e2160412d70e3b0a5e457c591581808a88be95bad86fce1db0418874863"
"pages/article/w-20261023-931cbfb61c.html|6544d01b8079ac17171f571eee1f29bf7ec1da1c12dcd9ae72dd061ed9c64073|de0e4ae7e6bdfcf17364273fca6cef4f9b388c60a174d3b8ddebaec2124a43ea"
"pages/article/w-20261024-ada755ff66.html|3d8576f65acbc52ec8b4cab6370f5bb5ca2e35582cfdc76c961ee61483d27889|328f519e9be4998011af1fcb9a72d7f170e47c9654e0b9e3e7fe3cc02f8c9a8d"
"pages/article/w-20261024-d4c9cfce14.html|fccd945fb87a345747ffbc000b36d45402b429bd844aacb2feed804fa331fe35|d5627272057d4d1fbe082da06053352989c6291f26199a87079d77d0630312cf"
"pages/article/w-20261101-1c5f069a6d.html|022c16f0403612e1fc9b043bd739ab8a9a5a391e7573af270896b9bf6ef0aa78|e55b35c264ab71199f67fc1763f5757b35b2d67b84783ff377a4120f4f7f0abd"
"pages/article/w-20261101-3c6a758ae8.html|0cf5f89d8729ca648301b2cc1b79267cf66be99325c14bc9bc9f825a5b61fee9|447b4c0e2caf759f1981e2a8ea5c682761e36048067c6f7644439f8827db0b6e"
"pages/article/w-20261101-a349af477f.html|5f0dc9d9dcd2ff8b499d37e8b9a72af3d3de1e68e666d75ab793f12300237eea|99b10698baf4f60bf597d5e547addcbf5782a6006272c62cfd8ba6ba919ee533"
"pages/article/w-20261101-bd15c9202b.html|59b935c05cbb96cd351b87f5b220ee32173a2e32483b86ae81209cbd0a73a061|364b8b67541b5fbb3988815a6ce6b77205ebb9c00ec7bc26af15cd3b9dc8f27b"
"pages/article/w-20261108-a623c210f3.html|8beeef0d73f28a6fcb4d1aa5f8144d318020424e54b8f9a3c8662307472e2967|63aefbc3096b06cd712a12f5c4348899534095e509207a988e8e705a2d40bd8d"
"pages/article/w-20261108-d23fd0c6d2.html|fede7d8b6249f7c6c28ddee3cbc5643d1541644666a605c08216f820ea5d1002|3deb2c911945b0a253238da12834372e51040e6953e1be233872df8566318016"
"pages/article/w-20261108-dde149ab25.html|441fa6ca35bce3168f1b06967bd343a648b241a700e4e6b9d77906939955e790|3e3d8b592a7504d6036cfb1e6be80ea3126a2a469b11b7e0b4b5a2f246243cba"
"pages/article/w-20261108-ed9af1abc2.html|6664adc8e96de744cc530c062edf5d4e2c7176ddff0f34bf14edf41886f0d1eb|7c78106a0bda9174a897cfe4dc447b04e19820f9a723471633208f5e68e70f44"
"pages/article/w-20261108-ff5a8f6e39.html|690ae1000664a13bfd16ffe99b1de0f0b457cf7f4ffda1ee0a1ba8edd0f80bf2|47204f815794a2306e5e853d7bbdba509a028fac763c6cd166485fee0feea72a"
"pages/article/w-20261115-741e920eae.html|761ebfb3711a801de71f3f2d358334143583103ebaef001980704c374297b42f|7033fa776a4541867014abeab9c49d6dd9f0f9550f24d0086f5234df8f1d0a3d"
"pages/article/w-20261115-96b394a9f8.html|c0fa234c114a26270fd8e6d7619cfa0268a56fc1c26164b48f486992e080f47c|7c2b7c3703ad3d5f705eea75246bc26435b659754222ae0058104600f3a1ab39"
"pages/article/w-20261123-41957df407.html|1a86a4053aa339d4f0b51d3a5a8c67f91996b5c853f89981df07daed045de9a1|02f59125c8888c3e5408571a96428e92ac94c7695d8032282ea27fa0d32cc210"
"pages/article/w-20261123-5cba2d70c7.html|f31bf8c36a55a104efe1a246ce7c05bce240e7dcdfeae2920bf3a77f5f00c7d5|abb159670d157e85a7c89bb0f7c71afd6348e0a745955c18680d75e4efa6464a"
"pages/article/w-20261123-6e7db8c70f.html|160a4d9994239b15257f073695c3cbf8550561fb38abbb296161039d99466846|5848bee591e75f64c68a19ed479db4fdcd795a01c9ddbf916f8711f283c64218"
"pages/article/w-20261123-c5736475d3.html|8975876c34021a858bef9a73a14830c33df6b528f53f3e43678121ebaf9ffb3c|e1ea44c8fb5d479ebb0e99b8af810feba4dbe5ba1e564b273cafcaca2382bc47"
"pages/article/w-20261123-d7402cc91c.html|75fe0deac7938b5b958454d5ecf2bf5a4683331ffee4f2fc3c61341d8e8b6d6e|18a8e1ec3dd06650e639bcf09a1c2dadb80110187162c449d55dfef577f4130f"
"pages/article/w-20261123-f63005a397.html|1fa506e098f1d1733064e7d294e11c721c03ddec774591d8262f41eca11864aa|4180f10e496cf762cbe1e782b1d2bfd698c5fede6ac54fa32881203d6892e00e"
"pages/article/w-20261123-fe93adb730.html|337c2de90be02ae949517e314532056288b85169704308b2aa45753d1934956e|939cc0e0fa8479644d4cbb00b1ef253a91e849b39773c9de240953b05038e453"
"pages/article/w-cartreg.html|99f07ff8aa7da785f0cca42c1d7a50cf946962e6b18c228a7e5b8e3ec1c603d8|10a4f401f84f64c504421611497c9e28538590380af714abf98ae641e9794760"
"pages/article/w-il15.html|065e0682cdb7894fd6f3b73a351c525e0917cb1e2462ff1b3e09694bcdb738dd|7ef78bdcf28537472abf8daaea3c44ea8ca2a1b14b66759924659389cb9c0eda"
"pages/article/w-medgemma.html|2cf81b3a05365d0405ecfea9473a9003d09621e1ba2f8fa79f1149aef66139c6|c50b4385a6ee9331817e753c64f6e9353bceaa751eec9c507f0d5499cb635899"
"pages/article/w-tem1657.html|21c885c8ebf71d15f209b1e775964917ab178966c1abb4a2a88b7709177e812f|4fad107ffac04d24f4f53dee6801e8dfb673da3073e22995efbe66283533328e"
"pages/newco-report.html|46dba787b054d4d04e54d884ff07dc7722b50bc70e60f413b853f48f0f2c0204|bb5db479ea7d7eac62290d0dbf0180d8308b0580fc7f4328abb71baea7dac49c"
"theramab/index.html|a0429e99a722adce23637e7574ff89eb79c1a355b2f6d9ad144c2daf120f1199|4ecea8c1646d846195c7c11ebf003e3b1956a68bf29dd1676fcba3c5e90692d5"
"therasik/index.html|2b03ddb6ea506eb183b65ff6f4a2908bbc3b495e58766b80c9d77e20cf8216c4|5013812fe0e5474bf1c4712fd57e9b00425305c93cb45da4a9f34bfe7078f35d"
)
NFILES=${#FILES[@]}
CANARIES=(
"content/talent/jobs_public.json|1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"
"assets/fonts/fonts.css|8228afd6527ba54591634f39ca6bfe8cb867ad88882da7a95d5da917d85aec60"
"feed.xml|a9ed23e1d035cf0a516cde094420f82687d35cfbb9d5d37896598ad72fc05be0"
"sitemap.xml|da8f0b54e0f915cc13c642fe95d07da154e266b0e883d6fd23d36469a83e39bb"
)
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261128_24e5321_baidu_v1}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261128_baidu_v1}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261128_baidu_v1.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"

curl_resolve=(); [[ -n "${CURL_RESOLVE:-}" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

echo "START baidu_v1 $TS ($NFILES html files; nginx locations untouched)" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
command -v perl >/dev/null || abort "perl missing" PERL
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
for e in "${FILES[@]}"; do
  IFS='|' read -r dest lsha nsha <<< "$e"
  [[ "$(sha "$CURRENT_ROOT/$dest")" == "$lsha" ]] || abort "live $dest is not the expected $lsha" DRIFT
done
for c in "${CANARIES[@]}"; do IFS='|' read -r p s <<< "$c"; [[ "$(sha "$CURRENT_ROOT/$p")" == "$s" ]] || abort "live $p drifted" DRIFT; done
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT BACKUP_BASE=$BACKUP_BASE" | tee -a "$LOG"

cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then mv "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled.$TS" && echo "INHERITED_ROLLBACK_PARKED" | tee -a "$LOG"; fi

export HM_ID="$SITE_ID"
for e in "${FILES[@]}"; do
  IFS='|' read -r dest lsha nsha <<< "$e"
  T="$NEW_REL_DIR/$dest"
  [[ "$(sha "$T")" == "$lsha" ]] || abort "copied $dest is not the known live version" STAGE
  # byte-exact insert before the first </head>; cat > keeps owner/mode of the copied file
  perl -0777 -e 'undef $/; my ($f,$o)=@ARGV; open(my $i,"<:raw",$f) or die; my $t=<$i>; close $i; die "dup" if $t=~/hm\.baidu\.com\/hm\.js/; my $id=$ENV{HM_ID}; my $s="<script>\nvar _hmt = _hmt || [];\n(function() {\n  var hm = document.createElement(\"script\");\n  hm.src = \"https://hm.baidu.com/hm.js?$id\";\n  var s = document.getElementsByTagName(\"script\")[0];\n  s.parentNode.insertBefore(hm, s);\n})();\n</script>\n"; $t=~s/<\/head>/$s<\/head>/ or die "nohead"; open(my $w,">:raw",$o) or die; print $w $t; close $w;' "$T" "$TMPD/f" || abort "insert failed for $dest" INSERT
  cat "$TMPD/f" > "$T" || abort "install $dest failed" INSTALL
  [[ "$(sha "$T")" == "$nsha" ]] || abort "staged $dest sha mismatch" STAGE
done

python3 - "$CURRENT_ROOT" "$NEW_REL_DIR" <<'PY' || abort "new root differs from live root beyond the 94 html files" STAGE_DIFF
import os, sys
old, new = sys.argv[1], sys.argv[2]
def walk(base):
    out=set()
    for root, dirs, files in os.walk(base):
        for fn in files: out.add(os.path.relpath(os.path.join(root, fn), base))
    return out
o, n = walk(old), walk(new)
bad=[x for x in sorted(n-o) if x!='rollback.sh']+['missing '+x for x in sorted(o-n) if x!='rollback.sh']
if bad: sys.stderr.write('UNEXPECTED:\n'+'\n'.join(bad[:20])+'\n'); sys.exit(1)
PY
for c in "${CANARIES[@]}"; do IFS='|' read -r p s <<< "$c"; [[ "$(sha "$NEW_REL_DIR/$p")" == "$s" ]] || abort "$p changed in staged root" STAGE; done
echo "STAGE_OK" | tee -a "$LOG"

BACKUP_CONF="${VHOST_CONF}.bak.baidu_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.baidu_v1.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-28 baidu_v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
set -uo pipefail
TS=\$(date +%Y%m%d_%H%M%S); V="$VHOST_CONF"
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)$NEW_REL_DIR;#\\\\1$CURRENT_ROOT;#" "\$V"
grep -qE "^[[:space:]]*root[[:space:]]+$CURRENT_ROOT;" "\$V" && ! grep -qF "$NEW_REL_DIR" "\$V" || { cp -a "$BACKUP_CONF" "\$V"; echo "vhost restored from backup $BACKUP_CONF"; }
NT=\$(nginx -t 2>&1); RC=\$?; echo "\$NT"
if [[ \$RC -ne 0 ]]; then cp -a "$BACKUP_CONF" "\$V"; NT=\$(nginx -t 2>&1); RC=\$?; echo "retry after full backup restore:"; echo "\$NT"; fi
[[ \$RC -eq 0 ]] || { echo ROLLBACK_FAIL_NGINX_T; exit 1; }
nginx -s reload || { echo ROLLBACK_FAIL_NGINX_RELOAD; exit 1; }
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh"
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_baidu_v1.sh"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  local nt rc; nt=$(nginx -t 2>&1); rc=$?; echo "$nt" | tee -a "$LOG"
  if [[ $rc -eq 0 ]]; then nginx -s reload >>"$LOG" 2>&1; echo "RESTORE_NGINX_T_OK" | tee -a "$LOG"; else echo "RESTORE_NGINX_T_FAIL" | tee -a "$LOG"; fi
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; exit 1; }

WEB_TOUCHED=1
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
NT=$(nginx -t 2>&1); NRC=$?; echo "$NT" >>"$LOG"
[[ $NRC -eq 0 ]] || { echo "$NT"; fail_restored "nginx -t failed" NGINX_TEST; }
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
sleep 1

VT="$TMPD/v.bin"
for e in "${FILES[@]}"; do
  IFS='|' read -r dest lsha nsha <<< "$e"
  path="$dest"; [[ "$dest" == "index.html" ]] && path=""
  ok=0; C=000
  for i in 1 2 3 4 5; do
    C=$(curl -s --retry 3 --retry-delay 2 "${curl_resolve[@]}" -o "$VT" -w '%{http_code}' "$SITE_ORIGIN/$path" || true)
    [[ "$C" == "200" && "$(sha "$VT")" == "$nsha" ]] && { ok=1; break; }; sleep 2
  done
  [[ "$ok" == "1" ]] || fail_restored "live /$path HTTP $C sha $(sha "$VT") is not the new file" VERIFY_FILE
done
echo "VERIFY_FILES_OK n=$NFILES (all contain hm.js?$SITE_ID)" | tee -a "$LOG"
for c in "${CANARIES[@]}"; do
  IFS='|' read -r p s <<< "$c"
  C=$(curl -s --retry 3 -o "$TMPD/c" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$p" || true)
  [[ "$C" == "200" && "$(sha "$TMPD/c")" == "$s" ]] || fail_restored "$p HTTP $C or sha changed" VERIFY_CANARY
done
echo "VERIFY_CANARIES_OK" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
